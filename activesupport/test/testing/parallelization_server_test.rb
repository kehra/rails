# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/testing/parallelization/server"

class ParallelizationServerTest < ActiveSupport::TestCase
  class FakeResultTest < ActiveSupport::TestCase
    def test_pass
      assert true
    end
  end

  test "push wraps reporter and adds test to distributor" do
    distributor = FakeDistributor.new
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: distributor)
    DRb.start_service("drbunix:", server)

    server << [FakeResultTest, :test_pass, Object.new]

    assert_equal 1, distributor.added.size
    assert_instance_of DRbObject, distributor.added.first[2]
  ensure
    DRb.stop_service
  end

  test "pop tracks in flight tests" do
    distributor = FakeDistributor.new
    distributor.to_take << [FakeResultTest, "test_pass", FakeReporter.new]
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: distributor)

    test = server.pop(1)

    assert_equal [FakeResultTest, "test_pass"], test[0, 2]
    assert_equal [["ParallelizationServerTest::FakeResultTest", "test_pass"]], server.instance_variable_get(:@in_flight).keys
    assert_nil server.pop(1)
  end

  test "record stores result through reporter and rejects unknown drb result" do
    distributor = FakeDistributor.new
    reporter = FakeReporter.new
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: distributor)
    result = Minitest::Result.from(FakeResultTest.new(:test_pass))
    server.instance_variable_get(:@in_flight)[[result.klass, result.name]] = :work

    server.record(reporter, result)

    assert_equal [[result.klass, result.name]], reporter.prerecorded
    assert_equal [result], reporter.recorded
    assert_empty server.instance_variable_get(:@in_flight)

    assert_raises(DRb::DRbConnError) do
      server.record(reporter, DRb::DRbUnknown.allocate)
    end
  end

  test "worker lifecycle and dead worker removal" do
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: FakeDistributor.new)

    assert_not server.active_workers?
    server.start_worker(1, 123)
    assert server.active_workers?
    server.remove_dead_workers([456])
    assert server.active_workers?
    server.remove_dead_workers([123])
    assert_not server.active_workers?

    server.start_worker(2, 789)
    server.stop_worker(2)
    assert_not server.active_workers?
  end

  test "interrupt delegates to distributor" do
    distributor = FakeDistributor.new
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: distributor)

    server.interrupt

    assert_equal true, distributor.interrupted
  end

  test "shutdown drains pending work and records missing in-flight results" do
    distributor = FakeDistributor.new(pending_results: [true, false])
    reporter = FakeReporter.new
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: distributor)
    server.define_singleton_method(:sleep) { |*| }
    server.instance_variable_get(:@in_flight)[[FakeResultTest.name, "test_pass"]] = [FakeResultTest, "test_pass", reporter]

    server.shutdown

    assert_equal true, distributor.closed
    assert_equal 1, reporter.recorded.size
    assert_match "result not reported", reporter.recorded.first.failures.first.error.message
  end

  test "wait_for_active_workers sleeps while workers are active" do
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: FakeDistributor.new)
    checks = [true, false]
    sleeps = 0
    server.define_singleton_method(:active_workers?) { checks.shift }
    server.define_singleton_method(:sleep) { |*| sleeps += 1 }

    server.send(:wait_for_active_workers)

    assert_equal 1, sleeps
  end

  test "shutdown handles interrupt while waiting" do
    distributor = FakeDistributor.new
    def distributor.pending?
      raise Interrupt
    end
    server = ActiveSupport::Testing::Parallelization::Server.new(distributor: distributor)

    _, err = capture_io do
      server.shutdown
    end

    assert_equal true, distributor.closed
    assert_match "Interrupted. Exiting", err
  end

  private
    class FakeDistributor
      attr_reader :added, :to_take
      attr_accessor :interrupted, :closed

      def initialize(pending_results: [false])
        @added = []
        @to_take = []
        @pending_results = pending_results
      end

      def add_test(test)
        @added << test
      end

      def take(worker_id:)
        @to_take.shift
      end

      def pending?
        @pending_results.shift || false
      end

      def close
        @closed = true
      end

      def interrupt
        @interrupted = true
      end
    end

    class FakeReporter
      attr_reader :prerecorded, :recorded

      def initialize
        @prerecorded = []
        @recorded = []
      end

      def synchronize
        yield
      end

      def prerecord(klass, name)
        @prerecorded << [klass.name, name]
      end

      def record(result)
        @recorded << result
      end
    end
end
