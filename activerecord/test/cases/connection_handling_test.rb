# frozen_string_literal: true

require "cases/helper"
require "models/post"

module ActiveRecord
  class ConnectionHandlingTest < ActiveRecord::TestCase
    fixtures :posts

    setup do
      @_permanent_connection_checkout_was = ActiveRecord.permanent_connection_checkout
    end

    teardown do
      ActiveRecord.permanent_connection_checkout = @_permanent_connection_checkout_was
    end

    unless in_memory_db?
      test "#with_connection lease the connection for the duration of the block" do
        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        ActiveRecord::Base.with_connection do |connection|
          assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        end

        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?
      end

      test "#lease_connection makes the lease permanent even inside #with_connection" do
        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        conn = nil
        ActiveRecord::Base.with_connection do |connection|
          conn = connection
          assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
          2.times do
            assert_same connection, ActiveRecord::Base.lease_connection
          end
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same conn, ActiveRecord::Base.lease_connection
      end

      test "#lease_connection makes the lease permanent even inside #with_connection(prevent_permanent_checkout: true)" do
        ActiveRecord::Base.release_connection

        ActiveRecord::Base.with_connection(prevent_permanent_checkout: true) do |connection|
          assert_same connection, ActiveRecord::Base.lease_connection
        end

        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?
      end

      test "#with_connection use the already leased connection if available" do
        leased_connection = ActiveRecord::Base.lease_connection
        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?

        ActiveRecord::Base.with_connection do |connection|
          assert_same leased_connection, connection
          assert_same ActiveRecord::Base.lease_connection, connection
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same ActiveRecord::Base.lease_connection, leased_connection
      end

      test "#with_connection is reentrant" do
        leased_connection = ActiveRecord::Base.lease_connection
        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?

        ActiveRecord::Base.with_connection do |connection|
          assert_same leased_connection, connection
          assert_same ActiveRecord::Base.lease_connection, connection

          ActiveRecord::Base.with_connection do |connection2|
            assert_same leased_connection, connection2
            assert_same ActiveRecord::Base.lease_connection, connection2
          end
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same ActiveRecord::Base.lease_connection, leased_connection
      end

      test "#connection is a soft-deprecated alias to #lease_connection" do
        ActiveRecord.permanent_connection_checkout = true

        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        conn = nil
        ActiveRecord::Base.with_connection do |connection|
          conn = connection
          assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
          2.times do
            assert_same connection, ActiveRecord::Base.connection
          end
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same conn, ActiveRecord::Base.connection

        ActiveRecord::Base.release_connection
      end

      test "#connection emits a deprecation warning if ActiveRecord.permanent_connection_checkout == :deprecated" do
        ActiveRecord.permanent_connection_checkout = :deprecated

        ActiveRecord::Base.release_connection

        assert_deprecated(ActiveRecord.deprecator) do
          ActiveRecord::Base.connection
        end

        assert_not_deprecated(ActiveRecord.deprecator) do
          ActiveRecord::Base.connection
        end

        ActiveRecord::Base.release_connection

        assert_deprecated(ActiveRecord.deprecator) do
          ActiveRecord::Base.connection
        end

        ActiveRecord::Base.release_connection

        ActiveRecord::Base.with_connection do
          assert_deprecated(ActiveRecord.deprecator) do
            ActiveRecord::Base.connection
          end
        end
      end

      test "#connection raises an error if ActiveRecord.permanent_connection_checkout == :disallowed" do
        ActiveRecord.permanent_connection_checkout = :disallowed

        ActiveRecord::Base.release_connection

        assert_raises(ActiveRecordError) do
          ActiveRecord::Base.connection
        end

        ActiveRecord::Base.with_connection do
          assert_raises(ActiveRecordError) do
            ActiveRecord::Base.connection
          end
        end

        ActiveRecord::Base.lease_connection

        assert_nothing_raised do
          ActiveRecord::Base.connection
        end
      end

      test "#connection doesn't make the lease permanent if inside #with_connection(prevent_permanent_checkout: true)" do
        ActiveRecord.permanent_connection_checkout = :disallowed

        ActiveRecord::Base.release_connection

        ActiveRecord::Base.with_connection(prevent_permanent_checkout: true) do |connection|
          assert_same connection, ActiveRecord::Base.connection
        end

        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?
      end

      test "common APIs don't permanently hold a connection when permanent checkout is deprecated or disallowed" do
        ActiveRecord.permanent_connection_checkout = :deprecated
        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        Post.create!(title: "foo", body: "bar")
        assert_not_predicate Post.connection_pool, :active_connection?

        Post.first
        assert_not_predicate Post.connection_pool, :active_connection?

        Post.count
        assert_not_predicate Post.connection_pool, :active_connection?
      end
    end

    test "#clear_query_caches_for_current_thread clears every connection pool" do
      pools = 2.times.map do
        pool = Object.new
        calls = []
        pool.define_singleton_method(:clear_query_cache) { calls << :clear_query_cache }
        pool.define_singleton_method(:calls) { calls }
        pool
      end
      handler = Object.new
      handler.define_singleton_method(:each_connection_pool) do |&block|
        pools.each(&block)
      end

      ActiveRecord::Base.stub(:connection_handler, handler) do
        ActiveRecord::Base.clear_query_caches_for_current_thread
      end

      assert_equal [[:clear_query_cache], [:clear_query_cache]], pools.map(&:calls)
    end

    test "#connected? delegates to the current connection specification role and shard" do
      handler = Object.new
      received = []
      handler.define_singleton_method(:connected?) do |specification_name, role:, shard:|
        received << [specification_name, role, shard]
        :connected_result
      end

      result = ActiveRecord::Base.stub(:connection_handler, handler) do
        ActiveRecord::Base.connected?
      end

      assert_equal :connected_result, result
      assert_equal [["ActiveRecord::Base", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard]], received
    end

    test "#connected_to validates receiver and requires a role or shard" do
      concrete_class = Class.new(ActiveRecord::Base)
      assert_raises(NotImplementedError) do
        concrete_class.connected_to(role: :writing) { flunk "should not yield" }
      end

      abstract_without_connection = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
      assert_raises(NotImplementedError) do
        abstract_without_connection.connected_to(role: :writing) { flunk "should not yield" }
      end

      assert_raises(ArgumentError) do
        ActiveRecord::Base.connected_to { flunk "should not yield" }
      end
    end

    test "#connected_to pushes role and shard for the block and restores afterward" do
      assert_equal ActiveRecord::Base.default_role, ActiveRecord::Base.current_role
      assert_equal ActiveRecord::Base.default_shard, ActiveRecord::Base.current_shard

      result = ActiveRecord::Base.connected_to(role: :reading, shard: :custom) do
        assert_equal :reading, ActiveRecord::Base.current_role
        assert_equal :custom, ActiveRecord::Base.current_shard
        assert ActiveRecord::Base.current_preventing_writes
        :block_result
      end

      assert_equal :block_result, result
      assert_equal ActiveRecord::Base.default_role, ActiveRecord::Base.current_role
      assert_equal ActiveRecord::Base.default_shard, ActiveRecord::Base.current_shard
    end

    test "#connected_to? compares role and shard against current stack" do
      ActiveRecord::Base.connected_to(role: :writing, shard: :custom) do
        assert ActiveRecord::Base.connected_to?(role: :writing, shard: :custom)
        assert_not ActiveRecord::Base.connected_to?(role: :reading, shard: :custom)
        assert_not ActiveRecord::Base.connected_to?(role: :writing, shard: :default)
      end
    end

    test "#connected_to_all_shards yields once for each configured shard" do
      yielded = []

      ActiveRecord::Base.stub(:shard_keys, [:default, :custom]) do
        results = ActiveRecord::Base.connected_to_all_shards(role: :writing) do
          yielded << ActiveRecord::Base.current_shard
          ActiveRecord::Base.current_shard
        end

        assert_equal [:default, :custom], results
      end

      assert_equal [:default, :custom], yielded
    end

    test "#connected_to_many applies one stack entry for flattened classes" do
      klass_one = Class.new(ActiveRecord::Base) { self.abstract_class = true }
      klass_two = Class.new(ActiveRecord::Base) { self.abstract_class = true }
      entry_inside_block = nil

      result = ActiveRecord::Base.connected_to_many([klass_one], klass_two, role: :reading, shard: :custom) do
        entry_inside_block = ActiveRecord::Base.connected_to_stack.last
        :many_result
      end

      assert_equal :many_result, result
      assert_equal :reading, entry_inside_block[:role]
      assert_equal :custom, entry_inside_block[:shard]
      assert_equal true, entry_inside_block[:prevent_writes]
      assert_equal [klass_one, klass_two], entry_inside_block[:klasses]
      assert_not_includes ActiveRecord::Base.connected_to_stack, entry_inside_block

      ActiveRecord::Base.connected_to_many(klass_one, role: :writing) do
        assert_equal false, ActiveRecord::Base.connected_to_stack.last[:prevent_writes]
      end
    end

    test "#connected_to_many validates receiver and class list" do
      klass = Class.new(ActiveRecord::Base) { self.abstract_class = true }

      assert_raises(NotImplementedError) do
        klass.connected_to_many(klass, role: :writing) { flunk "should not yield" }
      end

      assert_raises(NotImplementedError) do
        ActiveRecord::Base.connected_to_many(ActiveRecord::Base, role: :writing) { flunk "should not yield" }
      end
    end

    test "#connecting_to pushes a persistent stack entry" do
      previous_size = ActiveRecord::Base.connected_to_stack.size

      ActiveRecord::Base.connecting_to(role: :reading, shard: :custom)
      entry = ActiveRecord::Base.connected_to_stack.last

      assert_equal :reading, entry[:role]
      assert_equal :custom, entry[:shard]
      assert_equal true, entry[:prevent_writes]
      assert_equal [ActiveRecord::Base], entry[:klasses]

      ActiveRecord::Base.connected_to_stack.pop
      ActiveRecord::Base.connecting_to(role: :writing, shard: :default)
      entry = ActiveRecord::Base.connected_to_stack.last
      assert_equal false, entry[:prevent_writes]
    ensure
      ActiveRecord::Base.connected_to_stack.pop while ActiveRecord::Base.connected_to_stack.size > previous_size
    end
  end
end
