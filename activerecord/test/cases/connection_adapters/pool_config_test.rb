# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class PoolConfigTest < ActiveRecord::TestCase
      FakePool = Struct.new(:automatic_reconnect, :disconnect_calls, :discard_calls, keyword_init: true) do
        def disconnect!
          self.disconnect_calls += 1
        end

        def discard!
          self.discard_calls += 1
        end
      end

      def test_schema_reflection_is_built_from_lazy_schema_cache_path_and_can_be_overridden
        pool_config = new_pool_config

        assert_equal @db_config.lazy_schema_cache_path, pool_config.schema_reflection.instance_variable_get(:@cache_path)

        custom_reflection = Object.new
        pool_config.schema_reflection = custom_reflection

        assert_same custom_reflection, pool_config.schema_reflection
      end

      def test_initialize_stores_role_shard_db_config_and_connection_descriptor
        pool_config = new_pool_config(role: :reading, shard: :shard_one)

        assert_equal @db_config, pool_config.db_config
        assert_equal :reading, pool_config.role
        assert_equal :shard_one, pool_config.shard
        assert_equal ActiveRecord::Base.name, pool_config.connection_descriptor.name
        assert_predicate pool_config.connection_descriptor, :primary_class?
      end

      def test_connection_descriptor_accepts_existing_descriptor
        descriptor = ConnectionHandler::ConnectionDescriptor.new("custom", false)
        pool_config = PoolConfig.new(descriptor, @db_config, :writing, :default)

        assert_same descriptor, pool_config.connection_descriptor
      end

      def test_server_version_is_memoized_and_can_be_overridden
        connection = Class.new do
          attr_reader :calls

          def initialize
            @calls = 0
          end

          def get_database_version
            @calls += 1
            123
          end
        end.new
        pool_config = new_pool_config

        assert_equal 123, pool_config.server_version(connection)
        assert_equal 123, pool_config.server_version(connection)
        assert_equal 1, connection.calls

        pool_config.server_version = 456
        assert_equal 456, pool_config.server_version(connection)
        assert_equal 1, connection.calls
      end

      def test_pool_lazily_builds_connection_pool_once
        pool_config = new_pool_config

        pool = pool_config.pool

        assert_instance_of ConnectionPool, pool
        assert_same pool, pool_config.pool
      ensure
        pool&.disconnect!
      end

      def test_disconnect_returns_nil_without_pool_and_disconnects_existing_pool
        pool_config = new_pool_config

        assert_nil pool_config.disconnect!

        fake_pool = FakePool.new(automatic_reconnect: false, disconnect_calls: 0, discard_calls: 0)
        pool_config.instance_variable_set(:@pool, fake_pool)

        assert_nil pool_config.disconnect!(automatic_reconnect: true)
        assert fake_pool.automatic_reconnect
        assert_equal 1, fake_pool.disconnect_calls
      end

      def test_discard_pool_returns_nil_without_pool_and_clears_existing_pool
        pool_config = new_pool_config

        assert_nil pool_config.discard_pool!

        fake_pool = FakePool.new(automatic_reconnect: false, disconnect_calls: 0, discard_calls: 0)
        pool_config.instance_variable_set(:@pool, fake_pool)

        assert_equal 0, fake_pool.discard_calls
        assert_nil pool_config.discard_pool!
        assert_equal 1, fake_pool.discard_calls
        assert_nil pool_config.instance_variable_get(:@pool)
      end

      def test_disconnect_and_discard_return_nil_if_pool_disappears_inside_monitor
        disconnect_config = new_pool_config
        disconnect_pool = FakePool.new(automatic_reconnect: false, disconnect_calls: 0, discard_calls: 0)
        disconnect_config.instance_variable_set(:@pool, disconnect_pool)
        def disconnect_config.synchronize
          @pool = nil
          yield
        end

        assert_nil disconnect_config.disconnect!
        assert_equal 0, disconnect_pool.disconnect_calls

        discard_config = new_pool_config
        discard_pool = FakePool.new(automatic_reconnect: false, disconnect_calls: 0, discard_calls: 0)
        discard_config.instance_variable_set(:@pool, discard_pool)
        def discard_config.synchronize
          @pool = nil
          yield
        end

        assert_nil discard_config.discard_pool!
        assert_equal 0, discard_pool.discard_calls
      end

      def test_class_level_disconnect_all_and_discard_pools_visit_registered_instances
        original_instances = PoolConfig.const_get(:INSTANCES)
        isolated_instances = ObjectSpace::WeakMap.new
        PoolConfig.send(:remove_const, :INSTANCES)
        PoolConfig.const_set(:INSTANCES, isolated_instances)
        PoolConfig.send(:private_constant, :INSTANCES)

        disconnect_pool_config = new_pool_config
        disconnect_pool = FakePool.new(automatic_reconnect: false, disconnect_calls: 0, discard_calls: 0)
        disconnect_pool_config.instance_variable_set(:@pool, disconnect_pool)

        PoolConfig.disconnect_all!

        assert disconnect_pool.automatic_reconnect
        assert_equal 1, disconnect_pool.disconnect_calls

        discard_pool_config = new_pool_config
        discard_pool = FakePool.new(automatic_reconnect: false, disconnect_calls: 0, discard_calls: 0)
        discard_pool_config.instance_variable_set(:@pool, discard_pool)

        PoolConfig.discard_pools!

        assert_equal 1, discard_pool.discard_calls
        assert_nil discard_pool_config.instance_variable_get(:@pool)
      ensure
        if original_instances
          PoolConfig.send(:remove_const, :INSTANCES)
          PoolConfig.const_set(:INSTANCES, original_instances)
          PoolConfig.send(:private_constant, :INSTANCES)
        end
      end

      private
        def setup
          config = ActiveRecord::Base.connection_pool.db_config
          @db_config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
            config.env_name,
            "pool_config_test",
            config.configuration_hash.merge(schema_cache_path: "tmp/pool_config_test_schema_cache.yml")
          )
        end

        def new_pool_config(role: :writing, shard: :default)
          PoolConfig.new(ActiveRecord::Base, @db_config, role, shard)
        end
    end
  end
end
