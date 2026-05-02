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

    test "#connection uses lease or active connection according to pool lease mode" do
      pool = Class.new do
        attr_reader :leased, :active
        attr_accessor :permanent

        def initialize
          @leased = Object.new
          @active = Object.new
          @permanent = true
        end

        def permanent_lease? = @permanent
        def lease_connection = @leased
        def active_connection = @active
      end.new

      ActiveRecord.permanent_connection_checkout = true
      ActiveRecord::Base.stub(:connection_pool, pool) do
        assert_same pool.leased, ActiveRecord::Base.connection

        pool.permanent = false
        assert_same pool.active, ActiveRecord::Base.connection
      end
    end

    test "#connection warns or raises according to permanent checkout mode" do
      pool = Class.new do
        def permanent_lease? = true
        def lease_connection = :leased_connection
      end.new

      ActiveRecord::Base.stub(:connection_pool, pool) do
        ActiveRecord.permanent_connection_checkout = :deprecated
        assert_deprecated(ActiveRecord.deprecator) do
          assert_equal :leased_connection, ActiveRecord::Base.connection
        end

        ActiveRecord.permanent_connection_checkout = :disallowed
        assert_raises(ActiveRecordError) do
          ActiveRecord::Base.connection
        end
      end
    end

    test "#lease_connection delegates to the current connection pool" do
      pool = Object.new
      pool.define_singleton_method(:lease_connection) { :leased_connection }

      ActiveRecord::Base.stub(:connection_pool, pool) do
        assert_equal :leased_connection, ActiveRecord::Base.lease_connection
      end
    end

    test "#connection_db_config and #connection_pool delegate using current specification role and shard" do
      db_config = Object.new
      pool = Object.new
      pool.define_singleton_method(:db_config) { db_config }
      handler = Object.new
      received = []
      handler.define_singleton_method(:retrieve_connection_pool) do |specification_name, role:, shard:, strict: nil|
        received << [specification_name, role, shard, strict]
        pool
      end

      ActiveRecord::Base.stub(:connection_handler, handler) do
        assert_same pool, ActiveRecord::Base.connection_pool
        assert_same db_config, ActiveRecord::Base.connection_db_config
      end

      assert_equal [
        ["ActiveRecord::Base", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard, true],
        ["ActiveRecord::Base", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard, true],
      ], received
    end

    test "#connection_specification_name falls back to base or superclass and can be assigned" do
      base_had_spec = ActiveRecord::Base.instance_variable_defined?(:@connection_specification_name)
      base_spec = ActiveRecord::Base.instance_variable_get(:@connection_specification_name) if base_had_spec
      ActiveRecord::Base.remove_instance_variable(:@connection_specification_name) if base_had_spec

      assert_equal "ActiveRecord::Base", ActiveRecord::Base.connection_specification_name
    ensure
      ActiveRecord::Base.instance_variable_set(:@connection_specification_name, base_spec) if base_had_spec
    end

    test "#connection_specification_name inherits from superclass and can be assigned" do
      parent = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
        self.connection_specification_name = "ParentSpec"
      end
      child = Class.new(parent)

      assert_equal "ParentSpec", child.connection_specification_name

      child.connection_specification_name = "ChildSpec"
      assert_equal "ChildSpec", child.connection_specification_name
    end

    test "#establish_connection resolves config and delegates role and shard to handler" do
      config = Object.new
      configurations = Object.new
      resolved = []
      configurations.define_singleton_method(:resolve) do |value|
        resolved << value
        config
      end
      handler = Object.new
      established = []
      handler.define_singleton_method(:establish_connection) do |db_config, owner_name:, role:, shard:|
        established << [db_config, owner_name, role, shard]
        :established_connection
      end

      result = ActiveRecord::Base.stub(:configurations, configurations) do
        ActiveRecord::Base.stub(:connection_handler, handler) do
          ActiveRecord::Base.establish_connection(:writing_config)
        end
      end

      assert_equal :established_connection, result
      assert_equal [:writing_config], resolved
      assert_equal [[config, ActiveRecord::Base, ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard]], established
    end

    test "#connects_to validates receiver and mutually exclusive inputs" do
      concrete_class = Class.new(ActiveRecord::Base)
      assert_raises(NotImplementedError) do
        concrete_class.connects_to(database: { writing: :primary })
      end

      abstract_class = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
      assert_raises(ArgumentError) do
        abstract_class.connects_to(database: { writing: :primary }, shards: { default: { writing: :primary } })
      end
    end

    test "#connects_to establishes default database connections" do
      abstract_class = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
      abstract_class.define_singleton_method(:name) { "ConnectionHandlingTest::DefaultConnector" }
      configurations = Object.new
      configurations.define_singleton_method(:resolve) { |value| "config:#{value}" }
      handler = Object.new
      established = []
      handler.define_singleton_method(:establish_connection) do |db_config, owner_name:, role:, shard:|
        established << [db_config, owner_name, role, shard]
        "connection:#{role}:#{shard}"
      end

      connections = ActiveRecord::Base.stub(:configurations, configurations) do
        abstract_class.stub(:connection_handler, handler) do
          abstract_class.connects_to(database: { writing: :primary, reading: :replica })
        end
      end

      assert_equal ["connection:writing:default", "connection:reading:default"], connections
      assert_equal [], abstract_class.instance_variable_get(:@shard_keys)
      assert_equal [], abstract_class.stub(:connection_class_for_self, abstract_class) { abstract_class.shard_keys }
      assert_equal :default, abstract_class.default_shard
      assert abstract_class.connection_class?
      assert_equal [
        ["config:primary", abstract_class, :writing, :default],
        ["config:replica", abstract_class, :reading, :default],
      ], established
    ensure
      abstract_class.connection_class = false if abstract_class
    end

    test "#connects_to establishes sharded connections and preserves integer shard keys" do
      abstract_class = Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end
      abstract_class.define_singleton_method(:name) { "ConnectionHandlingTest::ShardedConnector" }
      configurations = Object.new
      configurations.define_singleton_method(:resolve) { |value| value }
      handler = Object.new
      established = []
      handler.define_singleton_method(:establish_connection) do |db_config, owner_name:, role:, shard:|
        established << [db_config, owner_name, role, shard]
        [db_config, role, shard]
      end

      connections = ActiveRecord::Base.stub(:configurations, configurations) do
        abstract_class.stub(:connection_handler, handler) do
          abstract_class.connects_to(shards: { "one" => { writing: :primary }, 2 => { reading: :replica } })
        end
      end

      assert_equal [[:primary, :writing, :one], [:replica, :reading, 2]], connections
      assert_equal ["one", 2], abstract_class.instance_variable_get(:@shard_keys)
      assert_equal ["one", 2], abstract_class.stub(:connection_class_for_self, abstract_class) { abstract_class.shard_keys }
      assert_equal "one", abstract_class.default_shard
      assert_equal [
        [:primary, abstract_class, :writing, :one],
        [:replica, abstract_class, :reading, 2],
      ], established
    ensure
      abstract_class.connection_class = false if abstract_class
    end

    test "#prohibit_shard_swapping toggles and restores per specification name" do
      previous = ActiveSupport::IsolatedExecutionState[:active_record_prohibit_shard_swapping]
      ActiveSupport::IsolatedExecutionState[:active_record_prohibit_shard_swapping] = Set.new(["other"])

      yielded = false
      ActiveRecord::Base.prohibit_shard_swapping do
        yielded = true
        assert ActiveRecord::Base.shard_swapping_prohibited?

        ActiveRecord::Base.prohibit_shard_swapping(false) do
          assert_not ActiveRecord::Base.shard_swapping_prohibited?
        end

        assert ActiveRecord::Base.shard_swapping_prohibited?
      end

      assert yielded
      assert_equal Set.new(["other"]), ActiveSupport::IsolatedExecutionState[:active_record_prohibit_shard_swapping]
    ensure
      ActiveSupport::IsolatedExecutionState[:active_record_prohibit_shard_swapping] = previous
    end

    test "remove_connection handles missing specification and missing pool" do
      had_spec = ActiveRecord::Base.instance_variable_defined?(:@connection_specification_name)
      spec = ActiveRecord::Base.instance_variable_get(:@connection_specification_name) if had_spec
      ActiveRecord::Base.remove_instance_variable(:@connection_specification_name) if had_spec
      handler = Object.new
      calls = []
      handler.define_singleton_method(:retrieve_connection_pool) do |specification_name, role:, shard:|
        calls << [:retrieve_connection_pool, specification_name, role, shard]
        nil
      end
      handler.define_singleton_method(:remove_connection_pool) do |specification_name, role:, shard:|
        calls << [:remove_connection_pool, specification_name, role, shard]
        :removed_without_pool
      end

      ActiveRecord::Base.stub(:connection_handler, handler) do
        assert_equal :removed_without_pool, ActiveRecord::Base.remove_connection
      end

      assert_equal [
        [:retrieve_connection_pool, nil, ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard],
        [:remove_connection_pool, nil, ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard],
      ], calls
    ensure
      ActiveRecord::Base.instance_variable_set(:@connection_specification_name, spec) if had_spec
    end

    test "release retrieve and remove connection delegate to handler and pool" do
      pool = Object.new
      pool.define_singleton_method(:release_connection) { :released_connection }
      handler = Object.new
      calls = []
      handler.define_singleton_method(:retrieve_connection) do |specification_name, role:, shard:|
        calls << [:retrieve_connection, specification_name, role, shard]
        :retrieved_connection
      end
      handler.define_singleton_method(:retrieve_connection_pool) do |specification_name, role:, shard:, strict: nil|
        calls << [:retrieve_connection_pool, specification_name, role, shard, strict]
        pool
      end
      handler.define_singleton_method(:remove_connection_pool) do |specification_name, role:, shard:|
        calls << [:remove_connection_pool, specification_name, role, shard]
        :removed_connection
      end

      ActiveRecord::Base.stub(:connection_handler, handler) do
        ActiveRecord::Base.stub(:connection_pool, pool) do
          assert_equal :released_connection, ActiveRecord::Base.release_connection
        end
        assert_equal :retrieved_connection, ActiveRecord::Base.retrieve_connection
        ActiveRecord::Base.connection_specification_name = "TemporarySpec"
        assert_equal :removed_connection, ActiveRecord::Base.remove_connection
        assert_equal "ActiveRecord::Base", ActiveRecord::Base.connection_specification_name
      end

      assert_equal [
        [:retrieve_connection, "ActiveRecord::Base", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard],
        [:retrieve_connection_pool, "TemporarySpec", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard, nil],
        [:remove_connection_pool, "TemporarySpec", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard],
      ], calls
    ensure
      ActiveRecord::Base.connection_specification_name = nil
    end
  end
end
