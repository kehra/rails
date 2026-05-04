# frozen_string_literal: true

require_relative "abstract_unit"

class ParallelizationTest < ActiveSupport::TestCase
  def setup
    @original_worker_id = ActiveSupport::TestCase.parallel_worker_id
  end

  def teardown
    ActiveSupport::TestCase.parallel_worker_id = @original_worker_id
  end

  test "parallel_worker_id is accessible as an attribute and method" do
    ActiveSupport::TestCase.parallel_worker_id = nil
    assert_nil ActiveSupport::TestCase.parallel_worker_id
    assert_nil parallel_worker_id
  end

  test "parallel_worker_id is set and accessible from class and instance" do
    ActiveSupport::TestCase.parallel_worker_id = 3

    assert_equal 3, ActiveSupport::TestCase.parallel_worker_id
    assert_equal 3, parallel_worker_id
  end

  test "parallel_worker_id persists across test subclasses" do
    ActiveSupport::TestCase.parallel_worker_id = 5

    subclass = Class.new(ActiveSupport::TestCase)
    assert_equal 5, subclass.parallel_worker_id

    instance = subclass.new("test")
    assert_equal 5, instance.parallel_worker_id
  end

  test "test order delegates to Active Support configuration" do
    original_order = ActiveSupport.test_order
    ActiveSupport.test_order = nil

    assert_equal :random, ActiveSupport::TestCase.test_order
    ActiveSupport::TestCase.test_order = :sorted
    assert_equal :sorted, ActiveSupport::TestCase.test_order
  ensure
    ActiveSupport.test_order = original_order
  end

  test "parallelize supports processor count and thread executor without database setting" do
    original_executor = Minitest.parallel_executor
    original_databases = ActiveSupport.parallelize_test_databases
    original_parallel_workers = ENV.delete("PARALLEL_WORKERS")

    ActiveSupport::TestCase.parallelize(workers: :number_of_processors, with: :threads, threshold: 1)

    executor = Minitest.parallel_executor
    assert_instance_of ActiveSupport::Testing::ParallelizeExecutor, executor
    assert_equal original_databases, ActiveSupport.parallelize_test_databases
  ensure
    ENV["PARALLEL_WORKERS"] = original_parallel_workers if original_parallel_workers
    Minitest.parallel_executor = original_executor
    ActiveSupport.parallelize_test_databases = original_databases
  end

  test "parallelize supports explicit process workers and database setting" do
    original_executor = Minitest.parallel_executor
    original_databases = ActiveSupport.parallelize_test_databases
    original_parallel_workers = ENV.delete("PARALLEL_WORKERS")

    ActiveSupport::TestCase.parallelize(workers: 2, with: :processes, parallelize_databases: false, threshold: 1)

    assert_instance_of ActiveSupport::Testing::ParallelizeExecutor, Minitest.parallel_executor
    assert_equal false, ActiveSupport.parallelize_test_databases
  ensure
    ENV["PARALLEL_WORKERS"] = original_parallel_workers if original_parallel_workers
    Minitest.parallel_executor = original_executor
    ActiveSupport.parallelize_test_databases = original_databases
  end

  test "parallelize environment variable overrides worker count" do
    original_executor = Minitest.parallel_executor
    original_parallel_workers = ENV["PARALLEL_WORKERS"]
    ENV["PARALLEL_WORKERS"] = "1"

    ActiveSupport::TestCase.parallelize(workers: :number_of_processors, with: :threads, threshold: 1)

    assert_instance_of ActiveSupport::Testing::ParallelizeExecutor, Minitest.parallel_executor
  ensure
    ENV["PARALLEL_WORKERS"] = original_parallel_workers
    Minitest.parallel_executor = original_executor
  end

  test "parallelize hooks are registered" do
    before_count = ActiveSupport::Testing::Parallelization.before_fork_hooks.size
    setup_count = ActiveSupport::Testing::Parallelization.after_fork_hooks.size
    teardown_count = ActiveSupport::Testing::Parallelization.run_cleanup_hooks.size

    ActiveSupport::TestCase.parallelize_before_fork { :before }
    ActiveSupport::TestCase.parallelize_setup { :setup }
    ActiveSupport::TestCase.parallelize_teardown { :teardown }

    assert_equal before_count + 1, ActiveSupport::Testing::Parallelization.before_fork_hooks.size
    assert_equal setup_count + 1, ActiveSupport::Testing::Parallelization.after_fork_hooks.size
    assert_equal teardown_count + 1, ActiveSupport::Testing::Parallelization.run_cleanup_hooks.size
  end

  test "test case inspect uses object identity string" do
    assert_match(/#<ParallelizationTest:/, inspect)
  end

  test "run order follows configured test order" do
    original_order = ActiveSupport.test_order
    ActiveSupport.test_order = :sorted

    assert_equal :sorted, ActiveSupport::TestCase.run_order
  ensure
    ActiveSupport.test_order = original_order
  end if ActiveSupport::TestCase.respond_to?(:run_order)

  test "parallelization exposes worker count size" do
    parallelization = ActiveSupport::Testing::Parallelization.new(2)

    assert_equal 2, parallelization.size
  ensure
    DRb.stop_service if defined?(DRb)
  end

  test "shutdown treats already reaped workers as dead" do
    parallelization = ActiveSupport::Testing::Parallelization.new(1)
    server = parallelization.instance_variable_get(:@queue_server)
    parallelization.instance_variable_set(:@worker_pool, [123])
    removed = nil
    shutdown_called = false
    server.define_singleton_method(:remove_dead_workers) { |workers| removed = workers }
    server.define_singleton_method(:shutdown) { shutdown_called = true }

    Process.stub(:waitpid, ->(*) { raise Errno::ECHILD }) do
      parallelization.shutdown
    end

    assert_equal [123], removed
    assert_equal true, shutdown_called
  ensure
    DRb.stop_service if defined?(DRb)
  end

  test "shutdown handles dead workers gracefully" do
    # Use a blocking queue strategy so workers wait for work
    blocking_distributor = ActiveSupport::Testing::Parallelization::SharedQueueDistributor.new

    parallelization = ActiveSupport::Testing::Parallelization.new(1)
    server = parallelization.instance_variable_get(:@queue_server)

    # Replace distributor with one that blocks
    server.instance_variable_set(:@distributor, blocking_distributor)

    parallelization.start

    sleep 0.5

    assert server.active_workers?

    worker_pids = parallelization.instance_variable_get(:@worker_pool)
    Process.kill("KILL", worker_pids.first)
    sleep 0.25

    Timeout.timeout(2.5, Minitest::Assertion, "Expected shutdown to not hang") { parallelization.shutdown }
    assert_not server.active_workers?
  end

  test "shutdown handles workers that die during server shutdown" do
    # Regression test: workers that exit without calling stop_worker AFTER
    # the initial WNOHANG sweep in Parallelization#shutdown must still be
    # detected inside Server#shutdown's wait_for_active_workers loop.
    parallelization = ActiveSupport::Testing::Parallelization.new(1)
    server = parallelization.instance_variable_get(:@queue_server)
    url = parallelization.instance_variable_get(:@url)

    # Use a shared queue distributor so the worker blocks waiting for work
    blocking_distributor = ActiveSupport::Testing::Parallelization::SharedQueueDistributor.new
    server.instance_variable_set(:@distributor, blocking_distributor)

    # Fork a worker that registers but will be killed mid-shutdown
    worker_pid = fork do
      DRb.stop_service
      queue = DRbObject.new_with_uri(url)
      queue.start_worker(0, Process.pid)
      sleep 5
      exit!(4)
    end
    parallelization.instance_variable_set(:@worker_pool, [worker_pid])

    sleep 0.25
    assert server.active_workers?

    # Schedule the kill AFTER shutdown begins, so the initial WNOHANG sweep
    # in Parallelization#shutdown finds the worker still alive
    Thread.new do
      sleep 0.5
      Process.kill("KILL", worker_pid)
    end

    Timeout.timeout(3, Minitest::Assertion, "Expected shutdown to not hang") { parallelization.shutdown }
    assert_not server.active_workers?
  end

  test "seeded distribution assigns tests to workers round-robin" do
    worker_count = 2

    # Simulate test collection
    tests = [
      ["TestClass1", "test_a", nil],
      ["TestClass1", "test_b", nil],
      ["TestClass2", "test_c", nil],
      ["TestClass2", "test_d", nil],
      ["TestClass3", "test_e", nil],
      ["TestClass3", "test_f", nil]
    ]

    # Mock seed and runnables before creating parallelization
    Minitest.stub :seed, 12345 do
      mock_runnable = Class.new do
        def self.runnable_methods
          ["test_a", "test_b"]
        end
      end

      Minitest::Runnable.stub :runnables, [mock_runnable, mock_runnable, mock_runnable] do
        parallelization = ActiveSupport::Testing::Parallelization.new(worker_count)

        # Access the distributor through the server
        server = parallelization.instance_variable_get(:@queue_server)
        distributor = server.instance_variable_get(:@distributor)

        # Verify it's a seeded distributor
        assert_instance_of ActiveSupport::Testing::Parallelization::RoundRobinDistributor, distributor

        # Enqueue tests - they'll be distributed round-robin immediately
        tests.each { |test| parallelization << test }

        # Close distributor to signal no more tests will come
        distributor.close

        # Collect tests from each worker by calling take
        worker_0_tests = []
        worker_1_tests = []

        # Drain worker 0's queue - should get tests at indexes 0, 2, 4
        while test = distributor.take(worker_id: 0)
          worker_0_tests << test
        end

        # Drain worker 1's queue - should get tests at indexes 1, 3, 5
        while test = distributor.take(worker_id: 1)
          worker_1_tests << test
        end

        # Verify all tests were distributed
        assert_equal tests.size, worker_0_tests.size + worker_1_tests.size

        # Verify round-robin distribution (each worker gets 3 tests)
        assert_equal 3, worker_0_tests.size
        assert_equal 3, worker_1_tests.size
      end
    end
  end

  test "seeded distribution produces same assignment with same seed" do
    worker_count = 2
    tests = [
      ["TestClass1", "test_a", nil],
      ["TestClass1", "test_b", nil],
      ["TestClass2", "test_c", nil],
      ["TestClass2", "test_d", nil]
    ]

    mock_runnable = Class.new do
      def self.runnable_methods
        ["test_a", "test_b"]
      end
    end

    # Run with same seed twice
    seed = 54321
    distributions = 2.times.map do
      Minitest.stub :seed, seed do
        Minitest::Runnable.stub :runnables, [mock_runnable, mock_runnable] do
          parallelization = ActiveSupport::Testing::Parallelization.new(worker_count)

          # Enqueue tests in same order (they arrive pre-shuffled from Minitest)
          tests.each { |test| parallelization << test }

          server = parallelization.instance_variable_get(:@queue_server)
          distributor = server.instance_variable_get(:@distributor)

          # Close to signal no more tests
          distributor.close

          # Drain all tests from all workers
          all_tests = []
          worker_count.times do |worker_id|
            while test = distributor.take(worker_id: worker_id)
              all_tests << [worker_id, test[0..1]]
            end
          end
          all_tests
        end
      end
    end

    # Verify both runs have identical distribution
    assert_equal distributions[0], distributions[1]
  end

  test "seeded distribution produces different assignment with different seed" do
    worker_count = 2

    mock_runnable = Class.new do
      def self.runnable_methods
        ["test_a", "test_b"]
      end
    end

    # Run with different seeds - this simulates Minitest shuffling tests differently
    distributions = [12345, 67890].map do |seed|
      Minitest.stub :seed, seed do
        Minitest::Runnable.stub :runnables, [mock_runnable, mock_runnable] do
          parallelization = ActiveSupport::Testing::Parallelization.new(worker_count)

          # Simulate tests arriving in different order based on seed
          # In reality, Minitest would shuffle these differently
          tests = [
            ["TestClass1", "test_a", nil],
            ["TestClass1", "test_b", nil],
            ["TestClass2", "test_c", nil],
            ["TestClass2", "test_d", nil]
          ].shuffle(random: Random.new(seed))

          tests.each { |test| parallelization << test }

          server = parallelization.instance_variable_get(:@queue_server)
          distributor = server.instance_variable_get(:@distributor)

          # Close to signal no more tests
          distributor.close

          # Capture which tests each worker gets, preserving order
          worker_tests = {}
          worker_count.times do |worker_id|
            worker_tests[worker_id] = []
            while test = distributor.take(worker_id: worker_id)
              worker_tests[worker_id] << test[0..1]
            end
          end
          worker_tests
        end
      end
    end

    # Verify different seeds produce different test assignments
    # Different seeds -> different Minitest shuffling -> different round-robin distribution
    assert_not_equal distributions[0], distributions[1]
  end

  test "default uses seeded distributor without work stealing" do
    mock_runnable = Class.new do
      def self.runnable_methods
        ["test_a"]
      end
    end

    Minitest::Runnable.stub :runnables, [mock_runnable] do
      parallelization = ActiveSupport::Testing::Parallelization.new(2)
      server = parallelization.instance_variable_get(:@queue_server)
      distributor = server.instance_variable_get(:@distributor)

      # Verify it's a seeded distributor
      assert_instance_of ActiveSupport::Testing::Parallelization::RoundRobinDistributor, distributor
    end
  end

  test "work_stealing: true uses seeded distributor with work stealing" do
    mock_runnable = Class.new do
      def self.runnable_methods
        ["test_a"]
      end
    end

    Minitest::Runnable.stub :runnables, [mock_runnable] do
      parallelization = ActiveSupport::Testing::Parallelization.new(2, work_stealing: true)
      server = parallelization.instance_variable_get(:@queue_server)
      distributor = server.instance_variable_get(:@distributor)

      # Verify it's a round robin work stealing distributor
      assert_instance_of ActiveSupport::Testing::Parallelization::RoundRobinWorkStealingDistributor, distributor
    end
  end

  test "thread pool executor uses seeded distributor by default" do
    mock_runnable = Class.new do
      def self.runnable_methods
        ["test_a"]
      end
    end

    Minitest.stub :seed, 12345 do
      Minitest::Runnable.stub :runnables, [mock_runnable] do
        executor = ActiveSupport::Testing::Parallelization::ThreadPoolExecutor.new(
          size: 2,
          distributor: ActiveSupport::Testing::Parallelization::RoundRobinDistributor.new(worker_count: 2)
        )

        # Verify the executor has the right interface
        assert_respond_to executor, :start
        assert_respond_to executor, :<<
        assert_respond_to executor, :shutdown
        assert_equal 2, executor.size
      end
    end
  end
end
