# frozen_string_literal: true

require "cases/helper"

class DatabaseConfigurationsTest < ActiveRecord::TestCase
  class FakeDatabaseConfigAdapter
    attr_reader :configuration_hash

    def initialize(configuration_hash)
      @configuration_hash = configuration_hash
    end
  end

  class ConcreteDatabaseConfig < ActiveRecord::DatabaseConfigurations::DatabaseConfig
    attr_reader :configuration_hash

    def initialize(env_name = "default_env", name = "primary", configuration_hash = {})
      super(env_name, name)
      @configuration_hash = configuration_hash
    end

    def adapter
      configuration_hash[:adapter]
    end
  end

  unless in_memory_db?
    def test_empty_returns_true_when_db_configs_are_empty
      old_config = ActiveRecord::Base.configurations
      config = {}

      ActiveRecord::Base.configurations = config

      assert_predicate ActiveRecord::Base.configurations, :empty?
      assert_predicate ActiveRecord::Base.configurations, :blank?
    ensure
      ActiveRecord::Base.configurations = old_config
    end
  end

  def test_configs_for_getter_with_env_name
    configs = ActiveRecord::Base.configurations.configs_for(env_name: "arunit")

    assert_equal 1, configs.size
    assert_equal ["arunit"], configs.map(&:env_name)
  end

  def test_configs_for_getter_with_name
    previous_env, ENV["RAILS_ENV"] = ENV["RAILS_ENV"], "arunit2"

    config = ActiveRecord::Base.configurations.configs_for(name: "primary")

    assert_equal "arunit2", config.env_name
    assert_equal "primary", config.name
  ensure
    ENV["RAILS_ENV"] = previous_env
  end

  def test_configs_for_with_name_symbol
    previous_env, ENV["RAILS_ENV"] = ENV["RAILS_ENV"], "arunit2"

    config = ActiveRecord::Base.configurations.configs_for(name: :primary)

    assert_equal "arunit2", config.env_name
    assert_equal "primary", config.name
  ensure
    ENV["RAILS_ENV"] = previous_env
  end

  def test_configs_for_getter_with_env_and_name
    config = ActiveRecord::Base.configurations.configs_for(env_name: "arunit", name: "primary")

    assert_equal "arunit", config.env_name
    assert_equal "primary", config.name
  end

  def test_find_db_config_returns_first_config_for_env
    config = ActiveRecord::DatabaseConfigurations.new({
        "test" => {
          "config_1" => {
            "adapter" => "abstract",
            "database" => "db"
          },
          "config_2" => {
            "adapter" => "abstract",
            "database" => "db"
          },
          "config_3" => {
            "adapter" => "abstract",
            "database" => "db"
          },
        }
      })

    assert_equal "config_1", config.find_db_config("test").name
  end

  def test_find_db_config_returns_a_db_config_object_for_the_given_env
    config = ActiveRecord::Base.configurations.find_db_config("arunit2")

    assert_equal "arunit2", config.env_name
    assert_equal "primary", config.name
  end

  def test_find_db_config_prioritize_db_config_object_for_the_current_env
    config = ActiveRecord::DatabaseConfigurations.new({
      "primary" => {
        "adapter" => "abstract",
      },
      ActiveRecord::ConnectionHandling::DEFAULT_ENV.call => {
        "primary" => {
          "adapter" => "sqlite3",
          "database" => ":memory:"
        }
      }
    }).find_db_config("primary")

    assert_equal "primary", config.name
    assert_equal ActiveRecord::ConnectionHandling::DEFAULT_ENV.call, config.env_name
    assert_equal ":memory:", config.database
  end

  class CustomHashConfig < ActiveRecord::DatabaseConfigurations::HashConfig
    def sharded?
      custom_config.fetch("sharded", false)
    end

    private
      def custom_config
        configuration_hash.fetch(:custom_config)
      end
  end

  def test_registering_a_custom_config_object
    previous_handlers = ActiveRecord::DatabaseConfigurations.db_config_handlers

    ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
      next unless config.key?(:custom_config)
      CustomHashConfig.new(env_name, name, config)
    end

    configs = ActiveRecord::DatabaseConfigurations.new({
      "test" => {
        "config_1" => {
          "adapter" => "abstract",
          "database" => "db",
          "custom_config" => {
            "sharded" => 1
          }
        },
        "config_2" => {
          "adapter" => "abstract",
          "database" => "db"
        }
      }
    }).configurations

    custom_config = configs.first
    hash_config = configs.last

    assert custom_config.is_a?(CustomHashConfig)
    assert hash_config.is_a?(ActiveRecord::DatabaseConfigurations::HashConfig)

    assert_predicate custom_config, :sharded?
  ensure
    ActiveRecord::DatabaseConfigurations.db_config_handlers = previous_handlers
  end

  def test_configs_for_with_custom_key
    previous_handlers = ActiveRecord::DatabaseConfigurations.db_config_handlers

    ActiveRecord::DatabaseConfigurations.register_db_config_handler do |env_name, name, _, config|
      next unless config.key?(:custom_config)
      CustomHashConfig.new(env_name, name, config)
    end

    config = {
      "default_env" => {
        "primary" => { "adapter" => "sqlite3", "database" => "test/db/primary.sqlite3", "custom_config" => { "sharded" => 1 } },
        "replica" => { "adapter" => "sqlite3", "database" => "test/db/hidden.sqlite3", "replica" => true, "custom_config" => { "sharded" => 1 } },
        "secondary" => { "adapter" => "sqlite3", "database" => "test/db/secondary.sqlite3" }
      }
    }
    prev_configs, ActiveRecord::Base.configurations = ActiveRecord::Base.configurations, config

    assert_equal 1, ActiveRecord::Base.configurations.configs_for(env_name: "default_env", config_key: :custom_config).count
    assert_equal 2, ActiveRecord::Base.configurations.configs_for(env_name: "default_env", config_key: :custom_config, include_hidden: true).count
    assert_equal 2, ActiveRecord::Base.configurations.configs_for(env_name: "default_env").count
  ensure
    ActiveRecord::DatabaseConfigurations.db_config_handlers = previous_handlers
    ActiveRecord::Base.configurations = prev_configs
  end

  def test_configs_for_with_include_hidden
    config = {
      "default_env" => {
        "readonly" => { "adapter" => "sqlite3", "database" => "test/db/readonly.sqlite3", "replica" => true },
        "hidden" => { "adapter" => "sqlite3", "database" => "test/db/hidden.sqlite3", "database_tasks" => false },
        "default" => { "adapter" => "sqlite3", "database" => "test/db/primary.sqlite3" }
      }
    }
    prev_configs, ActiveRecord::Base.configurations = ActiveRecord::Base.configurations, config

    assert_equal 1, ActiveRecord::Base.configurations.configs_for(env_name: "default_env").count
    assert_equal 3, ActiveRecord::Base.configurations.configs_for(env_name: "default_env", include_hidden: true).count
  ensure
    ActiveRecord::Base.configurations = prev_configs
  end

  def test_empty_and_blank_return_true_for_directly_empty_configurations
    configurations = ActiveRecord::DatabaseConfigurations.new([])

    assert_predicate configurations, :empty?
    assert_predicate configurations, :blank?
  end

  def test_initialize_accepts_existing_database_configurations_and_arrays
    hash_config = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", adapter: "sqlite3", database: "db/production.sqlite3")
    array_configurations = ActiveRecord::DatabaseConfigurations.new([hash_config])
    wrapped_configurations = ActiveRecord::DatabaseConfigurations.new(array_configurations)

    assert_same hash_config, array_configurations.configurations.first
    assert_same array_configurations.configurations, wrapped_configurations.configurations
  end

  def test_initialize_builds_url_configs_and_rejects_invalid_raw_configs
    configurations = ActiveRecord::DatabaseConfigurations.new(
      "production" => "sqlite3:///tmp/production.sqlite3"
    )

    assert_instance_of ActiveRecord::DatabaseConfigurations::UrlConfig, configurations.configurations.first
    assert_raises(ActiveRecord::DatabaseConfigurations::InvalidConfigurationError) do
      ActiveRecord::DatabaseConfigurations.new("production" => 123)
    end
    assert_raises(ActiveRecord::DatabaseConfigurations::InvalidConfigurationError) do
      ActiveRecord::DatabaseConfigurations.new("production" => "not-a-url")
    end
  end

  def test_hash_config_builder_returns_nil_when_all_registered_handlers_decline
    previous_handlers = ActiveRecord::DatabaseConfigurations.db_config_handlers
    ActiveRecord::DatabaseConfigurations.db_config_handlers = [->(_env_name, _name, _url, _config) {}]
    configurations = ActiveRecord::DatabaseConfigurations.allocate

    assert_nil configurations.send(:build_db_config_from_hash, "production", "primary", adapter: "sqlite3", database: "db/production.sqlite3")
  ensure
    ActiveRecord::DatabaseConfigurations.db_config_handlers = previous_handlers
  end

  def test_initialize_merges_database_url_for_current_environment
    previous_database_url = ENV["DATABASE_URL"]
    previous_env = ENV["RAILS_ENV"]
    ENV["DATABASE_URL"] = "sqlite3:///tmp/env-url.sqlite3"
    ENV["RAILS_ENV"] = "env_url"

    configurations = ActiveRecord::DatabaseConfigurations.new(
      "env_url" => { "primary" => { "adapter" => "sqlite3", "database" => "db/from_hash.sqlite3" } }
    )

    assert_instance_of ActiveRecord::DatabaseConfigurations::UrlConfig, configurations.configs_for(env_name: "env_url", name: "primary", include_hidden: true)
    assert_equal "/tmp/env-url.sqlite3", configurations.configs_for(env_name: "env_url", name: "primary", include_hidden: true).database
  ensure
    ENV["DATABASE_URL"] = previous_database_url
    ENV["RAILS_ENV"] = previous_env
  end

  def test_configs_for_without_env_name_returns_all_visible_configs
    configurations = ActiveRecord::DatabaseConfigurations.new(
      "production" => {
        "primary" => { "adapter" => "sqlite3", "database" => "db/production.sqlite3" },
        "replica" => { "adapter" => "sqlite3", "database" => "db/replica.sqlite3", "replica" => true }
      },
      "staging" => { "primary" => { "adapter" => "sqlite3", "database" => "db/staging.sqlite3" } }
    )

    assert_equal ["production:primary", "staging:primary"], configurations.configs_for.map { |config| "#{config.env_name}:#{config.name}" }
    assert_equal 3, configurations.configs_for(include_hidden: true).size
  end

  def test_database_config_base_contract_for_adapter_resolution_connection_and_validation
    config = ConcreteDatabaseConfig.new("production", "primary", adapter: "fake")
    calls = 0
    resolver = ->(adapter) do
      calls += 1
      assert_equal "fake", adapter
      FakeDatabaseConfigAdapter
    end

    ActiveRecord::ConnectionAdapters.stub(:resolve, resolver) do
      assert_same FakeDatabaseConfigAdapter, config.adapter_class
      assert_same FakeDatabaseConfigAdapter, config.adapter_class
      assert_equal 1, calls
      assert_equal({ adapter: "fake" }, config.new_connection.configuration_hash)
      assert config.validate!
      assert_match(/env_name=production name=primary adapter_class=DatabaseConfigurationsTest::FakeDatabaseConfigAdapter/, config.inspect)
    end
  end

  def test_database_config_validate_without_adapter_is_true
    assert ConcreteDatabaseConfig.new("production", "primary", {}).validate!
  end

  def test_database_config_for_current_env_matches_default_env
    current_config = ConcreteDatabaseConfig.new(ActiveRecord::ConnectionHandling::DEFAULT_ENV.call, "primary", {})
    other_config = ConcreteDatabaseConfig.new("elsewhere", "primary", {})

    assert_predicate current_config, :for_current_env?
    assert_not_predicate other_config, :for_current_env?
  end

  def test_database_config_abstract_methods_raise_not_implemented_error
    config = ActiveRecord::DatabaseConfigurations::DatabaseConfig.new("production", "primary")

    %i[
      host database _database= adapter min_connections max_connections min_threads max_threads
      max_queue query_cache checkout_timeout reaping_frequency idle_timeout replica?
      migrations_paths schema_cache_path use_metadata_table? seeds?
    ].each do |method_name|
      assert_raises(NotImplementedError) do
        method_name == :_database= ? config.public_send(method_name, "db/test.sqlite3") : config.public_send(method_name)
      end
    end
  end
end
