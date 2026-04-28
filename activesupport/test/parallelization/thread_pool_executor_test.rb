# frozen_string_literal: true

require_relative "../abstract_unit"

class ThreadPoolExecutorTest < ActiveSupport::TestCase
  test "executes tests in thread pool" do
    results = Concurrent::Array.new
    reporter = Minitest::CompositeReporter.new

    # Track which tests ran
    reporter.reporters << Class.new do
      define_method(:prerecord) { |*| }
      define_method(:record) { |result| results << result.name }
    end.new

    mock_test_class = Class.new(Minitest::Test) do
      def self.name
        "MockTest"
      end

      def test_foo
        assert true
      end

      def test_bar
        assert true
      end
    end

    distributor = ActiveSupport::Testing::Parallelization::RoundRobinDistributor.new(worker_count: 2)

    executor = ActiveSupport::Testing::Parallelization::ThreadPoolExecutor.new(
      size: 2,
      distributor: distributor
    )

    executor << [mock_test_class, "test_foo", reporter]
    executor << [mock_test_class, "test_bar", reporter]

    executor.start
    executor.shutdown

    assert_equal 2, results.size
    assert_includes results, "test_foo"
    assert_includes results, "test_bar"
  end

  test "worker loop uses minitest run_one_method when available" do
    reporter = Minitest::CompositeReporter.new
    results = []
    reporter.reporters << Class.new do
      attr_accessor :results
      define_method(:prerecord) { |*| }
      define_method(:record) { |result| results << result.name }
    end.new.tap { |r| r.results = results }

    mock_test_class = Class.new(Minitest::Test) do
      def self.name = "MockTest"
      def test_foo = assert(true)
    end

    distributor = ActiveSupport::Testing::Parallelization::RoundRobinDistributor.new(worker_count: 1)
    executor = ActiveSupport::Testing::Parallelization::ThreadPoolExecutor.new(size: 1, distributor: distributor)
    distributor.add_test([mock_test_class, "test_foo", reporter])
    distributor.close
    singleton = class << Minitest; self; end
    original_respond_to = Minitest.method(:respond_to?)
    original_run_one_method = Minitest.method(:run_one_method) if Minitest.respond_to?(:run_one_method)
    singleton.send(:define_method, :respond_to?) do |name, include_private = false|
      name == :run_one_method ? true : original_respond_to.call(name, include_private)
    end
    singleton.send(:define_method, :run_one_method) { |klass, method| klass.new(method).run }

    executor.send(:worker_loop, 0)
    assert_equal ["test_foo"], results
  ensure
    singleton.send(:define_method, :respond_to?, original_respond_to) if original_respond_to
    if original_run_one_method
      singleton.send(:define_method, :run_one_method, original_run_one_method)
    else
      singleton.send(:remove_method, :run_one_method) if Minitest.respond_to?(:run_one_method)
    end
  end

  test "worker loop supports minitest without run_one_method" do
    reporter = Minitest::CompositeReporter.new
    results = []
    reporter.reporters << Class.new do
      attr_accessor :results
      define_method(:prerecord) { |*| }
      define_method(:record) { |result| results << result.name }
    end.new.tap { |r| r.results = results }

    mock_test_class = Class.new(Minitest::Test) do
      def self.name = "MockTest"
      def test_foo = assert(true)
    end

    distributor = ActiveSupport::Testing::Parallelization::RoundRobinDistributor.new(worker_count: 1)
    executor = ActiveSupport::Testing::Parallelization::ThreadPoolExecutor.new(size: 1, distributor: distributor)
    distributor.add_test([mock_test_class, "test_foo", reporter])
    distributor.close

    singleton = class << Minitest; self; end
    original_respond_to = Minitest.method(:respond_to?)
    singleton.send(:define_method, :respond_to?) do |name, include_private = false|
      name == :run_one_method ? false : original_respond_to.call(name, include_private)
    end

    executor.send(:worker_loop, 0)
    assert_equal ["test_foo"], results
  ensure
    singleton.send(:define_method, :respond_to?, original_respond_to) if original_respond_to
  end

  test "distributes work using round robin distributor" do
    worker_assignments = Concurrent::Hash.new

    reporter = Minitest::CompositeReporter.new
    reporter.reporters << Class.new do
      attr_accessor :worker_assignments

      define_method(:prerecord) { |*| }
      define_method(:record) do |result|
        # Track which thread ran which test
        worker_assignments[Thread.current] ||= []
        worker_assignments[Thread.current] << result.name
      end
    end.new.tap { |r| r.worker_assignments = worker_assignments }

    mock_test_class = Class.new(Minitest::Test) do
      def self.name
        "MockTest"
      end

      def test_a; assert true; end
      def test_b; assert true; end
      def test_c; assert true; end
      def test_d; assert true; end
    end

    distributor = ActiveSupport::Testing::Parallelization::RoundRobinDistributor.new(worker_count: 2)

    distributor.add_test([mock_test_class, "test_a", reporter])
    distributor.add_test([mock_test_class, "test_b", reporter])
    distributor.add_test([mock_test_class, "test_c", reporter])
    distributor.add_test([mock_test_class, "test_d", reporter])

    executor = ActiveSupport::Testing::Parallelization::ThreadPoolExecutor.new(
      size: 2,
      distributor: distributor
    )

    executor.start
    executor.shutdown

    # Verify tests were distributed across threads
    assert_equal 2, worker_assignments.size
    assert worker_assignments.values.all? { |tests| tests.size > 0 }
  end
end
