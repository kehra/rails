# frozen_string_literal: true

require_relative "../abstract_unit"

class ParallelizeExecutorTest < ActiveSupport::TestCase
  test "process executor parallelizes above threshold and delegates lifecycle" do
    executor = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :processes, threshold: 0)
    fake = FakeParallelExecutor.new(size: 2)
    executor.define_singleton_method(:build_parallel_executor) { fake }

    out, = Minitest::Test.stub(:parallelize_me!, nil) { capture_io { executor.start } }
    executor << :work
    executor.shutdown

    assert_match "Running", out
    assert_equal true, fake.started
    assert_equal [:work], fake.work
    assert_equal true, fake.shutdown_called
  ensure
    Minitest::Test.parallel_executor = nil if Minitest::Test.respond_to?(:parallel_executor=)
  end

  test "does not delegate when below threshold" do
    old_parallel_workers = ENV.delete("PARALLEL_WORKERS")
    executor = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :processes, threshold: 10_000)
    fake = FakeParallelExecutor.new(size: 2)
    executor.define_singleton_method(:build_parallel_executor) { fake }

    out, = capture_io { executor.start }
    executor << :work
    executor.shutdown

    assert_match "single process", out
    assert_equal false, fake.started
    assert_empty fake.work
    assert_equal false, fake.shutdown_called
  ensure
    ENV["PARALLEL_WORKERS"] = old_parallel_workers if old_parallel_workers
  end

  test "does not parallelize with one worker" do
    old_parallel_workers = ENV.delete("PARALLEL_WORKERS")
    executor = ActiveSupport::Testing::ParallelizeExecutor.new(size: 1, with: :processes, threshold: 0)
    fake = FakeParallelExecutor.new(size: 1)
    executor.define_singleton_method(:build_parallel_executor) { fake }

    out, = capture_io { executor.start }

    assert_equal "\n", out
    assert_equal false, fake.started
  ensure
    ENV["PARALLEL_WORKERS"] = old_parallel_workers if old_parallel_workers
  end

  test "parallel workers environment bypasses threshold" do
    old_parallel_workers = ENV["PARALLEL_WORKERS"]
    ENV["PARALLEL_WORKERS"] = "2"
    executor = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :processes, threshold: 10_000)
    fake = FakeParallelExecutor.new(size: 2)
    executor.define_singleton_method(:build_parallel_executor) { fake }

    Minitest::Test.stub(:parallelize_me!, nil) { capture_io { executor.start } }

    assert_equal true, fake.started
  ensure
    ENV["PARALLEL_WORKERS"] = old_parallel_workers
  end

  test "builds process executor" do
    executor = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :processes, threshold: 0)

    assert_instance_of ActiveSupport::Testing::Parallelization, executor.send(:parallel_executor)
  end

  test "builds thread executor and work stealing executor" do
    singleton = class << ActiveSupport::TestCase; self; end
    singleton.send(:attr_accessor, :lock_threads)
    ActiveSupport::TestCase.lock_threads = true
    threads = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :threads, threshold: 0)
    thread_executor = threads.send(:parallel_executor)
    assert_instance_of ActiveSupport::Testing::Parallelization::ThreadPoolExecutor, thread_executor

    work_stealing = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :threads, threshold: 0, work_stealing: true)
    work_stealing_executor = work_stealing.send(:parallel_executor)
    assert_instance_of ActiveSupport::Testing::Parallelization::ThreadPoolExecutor, work_stealing_executor
    assert_equal false, ActiveSupport::TestCase.lock_threads

    singleton.send(:remove_method, :lock_threads) if singleton.method_defined?(:lock_threads)
    singleton.send(:remove_method, :lock_threads=) if singleton.method_defined?(:lock_threads=)
    without_lock_threads = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :threads, threshold: 0)
    assert_instance_of ActiveSupport::Testing::Parallelization::ThreadPoolExecutor, without_lock_threads.send(:parallel_executor)
  ensure
    singleton.send(:remove_method, :lock_threads) if singleton&.method_defined?(:lock_threads)
    singleton.send(:remove_method, :lock_threads=) if singleton&.method_defined?(:lock_threads=)
  end

  test "unsupported executor raises" do
    executor = ActiveSupport::Testing::ParallelizeExecutor.new(size: 2, with: :spaceships, threshold: 0)

    error = assert_raises(ArgumentError) { executor.send(:parallel_executor) }
    assert_match "spaceships is not a supported parallelization executor", error.message
  end

  private
    class FakeParallelExecutor
      attr_reader :size, :work
      attr_accessor :started, :shutdown_called

      def initialize(size:)
        @size = size
        @work = []
        @started = false
        @shutdown_called = false
      end

      def start
        @started = true
      end

      def <<(work)
        @work << work
      end

      def shutdown
        @shutdown_called = true
      end
    end
end
