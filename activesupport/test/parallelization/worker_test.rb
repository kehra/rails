# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/testing/parallelization/worker"

class ParallelizationWorkerTest < ActiveSupport::TestCase
  class FakeTest < ActiveSupport::TestCase
    def self.with_info_handler(_reporter = nil)
      yield
    end

    def test_pass
      assert true
    end
  end

  test "after_fork sets worker id and runs setup hooks" do
    worker = build_worker(3)
    calls = []
    hooks = ActiveSupport::Testing::Parallelization.after_fork_hooks
    hooks << ->(worker_id) { calls << worker_id }

    worker.after_fork

    assert_equal 3, ActiveSupport::TestCase.parallel_worker_id
    assert_equal [3], calls
  ensure
    hooks.pop if hooks&.last
    ActiveSupport::TestCase.parallel_worker_id = nil
  end

  test "run_cleanup runs cleanup hooks" do
    worker = build_worker(4)
    calls = []
    hooks = ActiveSupport::Testing::Parallelization.run_cleanup_hooks
    hooks << ->(worker_id) { calls << worker_id }

    worker.run_cleanup

    assert_equal [4], calls
  ensure
    hooks.pop if hooks&.last
  end

  test "perform_job runs test and records safely" do
    queue = FakeQueue.new
    worker = build_worker(1, queue: queue)
    reporter = FakeReporter.new
    singleton = class << Minitest; self; end
    original_respond_to = Minitest.method(:respond_to?)
    original_run_one_method = Minitest.method(:run_one_method) if Minitest.respond_to?(:run_one_method)
    singleton.send(:define_method, :respond_to?) do |name, include_private = false|
      name == :run_one_method ? true : original_respond_to.call(name, include_private)
    end
    singleton.send(:define_method, :run_one_method) { |klass, method| klass.new(method).run }

    worker.perform_job([FakeTest, "test_pass", reporter])

    assert_equal ["test_pass"], queue.recorded.map { |(_reporter, result)| result.name }
    assert_equal "Rails test worker 1 - (idle)", Process.getproctitle if Process.respond_to?(:getproctitle)
  ensure
    singleton.send(:define_method, :respond_to?, original_respond_to) if original_respond_to
    if original_run_one_method
      singleton.send(:define_method, :run_one_method, original_run_one_method)
    else
      singleton.send(:remove_method, :run_one_method) if Minitest.respond_to?(:run_one_method)
    end
  end

  test "perform_job supports minitest without run_one_method" do
    queue = FakeQueue.new
    worker = build_worker(1, queue: queue)
    reporter = FakeReporter.new
    singleton = class << Minitest; self; end
    original_respond_to = Minitest.method(:respond_to?)
    singleton.send(:define_method, :respond_to?) do |name, include_private = false|
      name == :run_one_method ? false : original_respond_to.call(name, include_private)
    end

    worker.perform_job([FakeTest, "test_pass", reporter])

    assert_equal ["test_pass"], queue.recorded.map { |(_reporter, result)| result.name }
  ensure
    singleton.send(:define_method, :respond_to?, original_respond_to) if original_respond_to
  end

  test "safe_record prepends setup exception and converts remote failures" do
    queue = FakeQueue.new(fail_once: true)
    worker = build_worker(2, queue: queue)
    worker.instance_variable_set(:@setup_exception, RuntimeError.new("setup failed"))
    result = Minitest::Result.from(FakeTest.new(:test_pass))
    result.failures << Minitest::UnexpectedError.new(RuntimeError.new("remote"))

    worker.safe_record(FakeReporter.new, result)

    assert_equal 2, queue.recorded.size
    failures = queue.recorded.last.last.failures
    assert_match "setup failed", failures.first.error.message
    assert_instance_of DRb::DRbRemoteError, failures.last.error
  end

  test "safe_record converts legacy exception failures" do
    queue = FakeQueue.new(fail_once: true)
    worker = build_worker(2, queue: queue)
    result = Minitest::Result.from(FakeTest.new(:test_pass))
    result.failures << LegacyFailure.new(RuntimeError.new("legacy"))

    worker.safe_record(FakeReporter.new, result)

    assert_instance_of DRb::DRbRemoteError, queue.recorded.last.last.failures.first.error
  end

  test "work_from_queue performs queued jobs until nil" do
    queue = FakeQueue.new
    reporter = FakeReporter.new
    queue.jobs << [FakeTest, "test_pass", reporter]
    worker = build_worker(5, queue: queue)

    worker.work_from_queue

    assert_equal 1, queue.recorded.size
    assert_equal [5, 5], queue.popped_worker_ids
  end

  test "start forks worker lifecycle" do
    worker = build_worker(6)
    queue = FakeQueue.new
    worker.define_singleton_method(:fork) { |&block| block.call; 123 }
    worker.define_singleton_method(:set_process_title) { |*| }
    worker.define_singleton_method(:after_fork) { }
    worker.define_singleton_method(:work_from_queue) { }
    DRb.stub(:stop_service, nil) do
      DRbObject.stub(:new_with_uri, queue) do
        assert_equal 123, worker.start
      end
    end
    assert_equal [[worker.instance_variable_get(:@id), Process.pid]], queue.started
    assert_equal [worker.instance_variable_get(:@id)], queue.stopped
  end

  test "start interrupts queue on interrupt" do
    worker = build_worker(7)
    queue = FakeQueue.new
    worker.define_singleton_method(:fork) { |&block| block.call; 123 }
    worker.define_singleton_method(:set_process_title) { |*| }
    worker.define_singleton_method(:after_fork) { }
    worker.define_singleton_method(:work_from_queue) { raise Interrupt }
    DRb.stub(:stop_service, nil) do
      DRbObject.stub(:new_with_uri, queue) do
        worker.start
      end
    end
    assert_equal true, queue.interrupted
  end

  private
    def build_worker(number, queue: FakeQueue.new)
      ActiveSupport::Testing::Parallelization::Worker.new(number, "druby://example").tap do |worker|
        worker.instance_variable_set(:@queue, queue)
      end
    end

    class FakeReporter; end

    class FakeQueue
      attr_reader :recorded, :jobs, :popped_worker_ids, :started, :stopped
      attr_accessor :interrupted

      def initialize(fail_once: false)
        @fail_once = fail_once
        @recorded = []
        @jobs = []
        @popped_worker_ids = []
        @started = []
        @stopped = []
      end

      def record(reporter, result)
        @recorded << [reporter, result]
        if @fail_once
          @fail_once = false
          raise DRb::DRbConnError
        end
      end

      def pop(worker_id)
        @popped_worker_ids << worker_id
        @jobs.shift
      end

      def start_worker(id, pid)
        @started << [id, pid]
      end

      def stop_worker(id)
        @stopped << id
      end

      def interrupt
        @interrupted = true
      end
    end

    class LegacyFailure
      attr_reader :exception
      def initialize(exception)
        @exception = exception
      end
    end
end
