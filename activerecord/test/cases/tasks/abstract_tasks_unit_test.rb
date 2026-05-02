# frozen_string_literal: true

require "cases/helper"
require "active_record/tasks/abstract_tasks"

module ActiveRecord
  module Tasks
    class AbstractTasksUnitTest < ActiveRecord::TestCase
      FakeDbConfig = Struct.new(:configuration_hash)
      FakeConnection = Struct.new(:encoding, :collation)
      FakePool = Struct.new(:migration_context)
      FakeMigrationContext = Struct.new(:current_environment, :last_stored_environment, :protected_environment?)
      class NoDatabasePool
        def migration_context
          raise ActiveRecord::NoDatabaseError.new
        end
      end

      class TestTasks < AbstractTasks
        attr_accessor :connection_to_return, :pool_to_yield, :error_to_raise
        attr_reader :temporary_pool_calls

        def initialize(db_config)
          super
          @temporary_pool_calls = []
        end

        private
          def connection
            connection_to_return
          end

          def with_temporary_pool(db_config, migration_class, clobber: false)
            @temporary_pool_calls << [db_config, migration_class, clobber]
            raise error_to_raise if error_to_raise
            yield pool_to_yield
          end
      end

      def test_using_database_configurations_is_true
        assert ActiveRecord::Tasks::AbstractTasks.using_database_configurations?
      end

      def test_initializes_with_db_config_and_configuration_hash
        db_config = FakeDbConfig.new({ database: "app_test", adapter: "sqlite3" })
        tasks = TestTasks.new(db_config)

        assert_same db_config, tasks.send(:db_config)
        assert_equal({ database: "app_test", adapter: "sqlite3" }, tasks.send(:configuration_hash))
        assert_equal({ database: nil, adapter: "sqlite3" }, tasks.send(:configuration_hash_without_database))
      end

      def test_charset_and_collation_delegate_to_connection
        tasks = TestTasks.new(FakeDbConfig.new({}))
        tasks.connection_to_return = FakeConnection.new("utf8mb4", "utf8mb4_unicode_ci")

        assert_equal "utf8mb4", tasks.charset
        assert_equal "utf8mb4_unicode_ci", tasks.collation
      end

      def test_check_current_protected_environment_raises_for_protected_environment
        tasks = TestTasks.new(FakeDbConfig.new({}))
        tasks.pool_to_yield = FakePool.new(FakeMigrationContext.new("development", "production", true))

        error = assert_raises(ActiveRecord::ProtectedEnvironmentError) do
          tasks.check_current_protected_environment!(:db_config, :migration_class)
        end

        assert_includes error.message, "production"
        assert_equal [[:db_config, :migration_class, false]], tasks.temporary_pool_calls
      end

      def test_check_current_protected_environment_raises_for_environment_mismatch
        tasks = TestTasks.new(FakeDbConfig.new({}))
        tasks.pool_to_yield = FakePool.new(FakeMigrationContext.new("development", "test", false))

        error = assert_raises(ActiveRecord::EnvironmentMismatchError) do
          tasks.check_current_protected_environment!(:db_config, :migration_class)
        end

        assert_includes error.message, "development"
        assert_includes error.message, "test"
      end

      def test_check_current_protected_environment_allows_matching_or_empty_stored_environment
        tasks = TestTasks.new(FakeDbConfig.new({}))
        tasks.pool_to_yield = FakePool.new(FakeMigrationContext.new("development", "development", false))
        assert_nothing_raised { tasks.check_current_protected_environment!(:db_config, :migration_class) }

        tasks.pool_to_yield = FakePool.new(FakeMigrationContext.new("development", nil, false))
        assert_nothing_raised { tasks.check_current_protected_environment!(:db_config, :migration_class) }
      end

      def test_check_current_protected_environment_ignores_missing_database
        tasks = TestTasks.new(FakeDbConfig.new({}))
        tasks.pool_to_yield = NoDatabasePool.new

        assert_nothing_raised { tasks.check_current_protected_environment!(:db_config, :migration_class) }
      end

      def test_private_connection_helpers_delegate_to_active_record_base
        db_config = FakeDbConfig.new({})
        tasks = ActiveRecord::Tasks::AbstractTasks.new(db_config)
        connection = Object.new
        established = []

        ActiveRecord::Base.stub(:lease_connection, connection) do
          assert_same connection, tasks.send(:connection)
        end

        ActiveRecord::Base.stub(:establish_connection, ->(config) { established << config }) do
          tasks.send(:establish_connection)
          tasks.send(:establish_connection, :other_config)
        end

        assert_equal [db_config, :other_config], established
      end

      def test_run_cmd_and_error_message
        tasks = TestTasks.new(FakeDbConfig.new({}))

        Kernel.stub(:system, true) do
          assert_nil tasks.send(:run_cmd, "ruby", "-v")
        end

        Kernel.stub(:system, false) do
          error = assert_raises(RuntimeError) { tasks.send(:run_cmd, "missing", "--version") }
          assert_includes error.message, "failed to execute:"
          assert_includes error.message, "missing --version"
          assert_includes error.message, "installed in your PATH"
        end
      end

      def test_with_temporary_pool_yields_pool_and_restores_original_connection
        tasks = ActiveRecord::Tasks::AbstractTasks.new(FakeDbConfig.new({}))
        original_config = :original_config
        established = []
        handler = Class.new do
          attr_reader :established, :pool

          def initialize(established)
            @established = established
            @pool = Object.new
          end

          def establish_connection(config, clobber: false)
            established << [config, clobber]
            pool
          end
        end.new(established)
        migration_class = Struct.new(:connection_db_config, :connection_handler).new(original_config, handler)

        yielded_pool = tasks.send(:with_temporary_pool, :temporary_config, migration_class, clobber: true) { |pool| pool }

        assert_same handler.pool, yielded_pool
        assert_equal [[:temporary_config, true], [original_config, true]], established
      end
    end
  end
end
