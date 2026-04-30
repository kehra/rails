# frozen_string_literal: true

require "cases/helper"
require "active_record/test_databases"

class TestDatabasesUnitTest < ActiveRecord::TestCase
  def test_before_fork_hook_clears_connections_only_when_parallel_test_databases_enabled
    hook = test_databases_hook(ActiveSupport::Testing::Parallelization.before_fork_hooks)
    handler = Minitest::Mock.new
    handler.expect(:clear_all_connections!, nil)
    previous = ActiveSupport.parallelize_test_databases

    ActiveSupport.parallelize_test_databases = true
    ActiveRecord::Base.stub(:connection_handler, handler) { hook.call }
    handler.verify

    ActiveSupport.parallelize_test_databases = false
    ActiveRecord::Base.stub(:connection_handler, flunking_connection_handler(:clear_all_connections!)) { hook.call }
    assert true
  ensure
    ActiveSupport.parallelize_test_databases = previous
  end

  def test_after_fork_hook_creates_schema_only_when_parallel_test_databases_enabled
    hook = test_databases_hook(ActiveSupport::Testing::Parallelization.after_fork_hooks)
    previous = ActiveSupport.parallelize_test_databases
    calls = []

    ActiveSupport.parallelize_test_databases = true
    ActiveRecord::TestDatabases.stub(:create_and_load_schema, ->(i, env_name:) { calls << [i, env_name] }) do
      hook.call(7)
    end
    assert_equal [[7, ActiveRecord::ConnectionHandling::DEFAULT_ENV.call]], calls

    ActiveSupport.parallelize_test_databases = false
    ActiveRecord::TestDatabases.stub(:create_and_load_schema, ->(*) { flunk("should not create test databases") }) do
      hook.call(8)
    end
  ensure
    ActiveSupport.parallelize_test_databases = previous
  end

  def test_create_and_load_schema_suffixes_hidden_configs_and_only_reconstructs_database_task_configs
    previous_verbose, ENV["VERBOSE"] = ENV["VERBOSE"], "true"
    previous_configs = ActiveRecord::Base.configurations
    ActiveRecord::Base.configurations = {
      "unit" => {
        "primary" => { "adapter" => "sqlite3", "database" => "primary.sqlite3" },
        "replica" => { "adapter" => "sqlite3", "database" => "replica.sqlite3", "replica" => true },
        "schema_only" => { "adapter" => "sqlite3", "database" => "schema_only.sqlite3", "database_tasks" => false }
      }
    }
    calls = []

    ActiveRecord::Base.stub(:establish_connection, -> { calls << [:establish_connection, ENV["VERBOSE"]] }) do
      ActiveRecord::Tasks::DatabaseTasks.stub(:reconstruct_from_schema, ->(db_config, file) { calls << [db_config.name, db_config.database, file, ENV["VERBOSE"]] }) do
        ActiveRecord::TestDatabases.create_and_load_schema(3, env_name: "unit")
      end
    end

    assert_includes calls, ["primary", "primary.sqlite3_3", nil, "false"]
    assert_not calls.any? { |entry| entry.first == "replica" }
    assert_not calls.any? { |entry| entry.first == "schema_only" }
    assert_includes calls, [:establish_connection, "false"]
    assert_equal "true", ENV["VERBOSE"]
    assert_equal "primary.sqlite3_3", ActiveRecord::Base.configurations.configs_for(env_name: "unit", name: "primary").database
    assert_equal "replica.sqlite3_3", ActiveRecord::Base.configurations.configs_for(env_name: "unit", name: "replica", include_hidden: true).database
    assert_equal "schema_only.sqlite3_3", ActiveRecord::Base.configurations.configs_for(env_name: "unit", name: "schema_only", include_hidden: true).database
  ensure
    ActiveRecord::Base.configurations = previous_configs
    ENV["VERBOSE"] = previous_verbose
  end

  def test_create_and_load_schema_restores_verbose_and_connection_when_reconstruct_raises
    previous_verbose, ENV["VERBOSE"] = ENV["VERBOSE"], nil
    previous_configs = ActiveRecord::Base.configurations
    ActiveRecord::Base.configurations = {
      "unit" => {
        "primary" => { "adapter" => "sqlite3", "database" => "primary.sqlite3" }
      }
    }
    established = false

    assert_raises(RuntimeError) do
      ActiveRecord::Base.stub(:establish_connection, -> { established = true }) do
        ActiveRecord::Tasks::DatabaseTasks.stub(:reconstruct_from_schema, ->(*) { raise "boom" }) do
          ActiveRecord::TestDatabases.create_and_load_schema(4, env_name: "unit")
        end
      end
    end

    assert established
    assert_nil ENV["VERBOSE"]
  ensure
    ActiveRecord::Base.configurations = previous_configs
    ENV["VERBOSE"] = previous_verbose
  end

  private
    def test_databases_hook(hooks)
      hooks.reverse.find { |hook| hook.source_location&.first&.end_with?("active_record/test_databases.rb") }
    end

    def flunking_connection_handler(method_name)
      Object.new.tap do |handler|
        handler.define_singleton_method(method_name) { flunk("#{method_name} should not be called") }
      end
    end
end
