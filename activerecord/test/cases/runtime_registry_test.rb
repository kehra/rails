# frozen_string_literal: true

require "cases/helper"
require "active_record/runtime_registry"

module ActiveRecord
  class RuntimeRegistryTest < ActiveRecord::TestCase
    setup do
      @previous_runtime = ActiveSupport::IsolatedExecutionState[:active_record_runtime]
      ActiveSupport::IsolatedExecutionState[:active_record_runtime] = nil
    end

    teardown do
      ActiveSupport::IsolatedExecutionState[:active_record_runtime] = @previous_runtime
    end

    test "stats are initialized and reused for current isolated execution state" do
      stats = RuntimeRegistry.stats

      assert_same stats, RuntimeRegistry.stats
      assert_equal 0.0, stats.sql_runtime
      assert_equal 0.0, stats.async_sql_runtime
      assert_equal 0, stats.queries_count
      assert_equal 0, stats.cached_queries_count
    end

    test "record accumulates query counts cache counts and runtimes" do
      RuntimeRegistry.record("User Load", 10.5)
      RuntimeRegistry.record("Cached Load", 2.0, cached: true)

      stats = RuntimeRegistry.stats
      assert_equal 12.5, stats.sql_runtime
      assert_equal 0.0, stats.async_sql_runtime
      assert_equal 2, stats.queries_count
      assert_equal 1, stats.cached_queries_count
    end

    test "record skips transaction and schema query counts but keeps runtime" do
      RuntimeRegistry.record("TRANSACTION", 1.5, cached: true)
      RuntimeRegistry.record("SCHEMA", 2.5, cached: true)

      stats = RuntimeRegistry.stats
      assert_equal 4.0, stats.sql_runtime
      assert_equal 0, stats.queries_count
      assert_equal 0, stats.cached_queries_count
    end

    test "record tracks async runtime without lock wait" do
      RuntimeRegistry.record("Async Load", 12.0, async: true, lock_wait: 3.5)

      stats = RuntimeRegistry.stats
      assert_equal 12.0, stats.sql_runtime
      assert_equal 8.5, stats.async_sql_runtime
      assert_equal 1, stats.queries_count
    end

    test "call records sql active record notification payload" do
      RuntimeRegistry.call("sql.active_record", 1.0, 1.125, "id", { name: "User Load", cached: true, async: true, lock_wait: 25.0 })

      stats = RuntimeRegistry.stats
      assert_equal 125.0, stats.sql_runtime
      assert_equal 100.0, stats.async_sql_runtime
      assert_equal 1, stats.queries_count
      assert_equal 1, stats.cached_queries_count
    end

    test "reset_runtimes returns previous sql runtime and clears runtime totals" do
      RuntimeRegistry.record("User Load", 7.0, async: true, lock_wait: 2.0)

      previous_runtime = RuntimeRegistry.stats.reset_runtimes

      assert_equal 7.0, previous_runtime
      assert_equal 0.0, RuntimeRegistry.stats.sql_runtime
      assert_equal 0.0, RuntimeRegistry.stats.async_sql_runtime
      assert_equal 1, RuntimeRegistry.stats.queries_count
    end

    test "reset restores all counters" do
      RuntimeRegistry.record("User Load", 7.0, cached: true, async: true, lock_wait: 2.0)

      RuntimeRegistry.reset

      stats = RuntimeRegistry.stats
      assert_equal 0.0, stats.sql_runtime
      assert_equal 0.0, stats.async_sql_runtime
      assert_equal 0, stats.queries_count
      assert_equal 0, stats.cached_queries_count
    end
  end
end
