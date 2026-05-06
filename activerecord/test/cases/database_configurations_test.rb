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
    env_name = "arunit2"

    ActiveRecord::ConnectionHandling::RAILS_ENV.stub(:call, env_name) do
      config = ActiveRecord::Base.configurations.configs_for(name: "primary")

      assert_equal env_name, config.env_name
      assert_equal "primary", config.name
    end
  end

  def test_configs_for_with_name_symbol
    env_name = "arunit2"

    ActiveRecord::ConnectionHandling::RAILS_ENV.stub(:call, env_name) do
      config = ActiveRecord::Base.configurations.configs_for(name: :primary)

      assert_equal env_name, config.env_name
      assert_equal "primary", config.name
    end
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
    ENV["DATABASE_URL"] = "sqlite3:///tmp/env-url.sqlite3"
    env_name = "env_url"

    ActiveRecord::ConnectionHandling::RAILS_ENV.stub(:call, env_name) do
      configurations = ActiveRecord::DatabaseConfigurations.new(
        env_name => { "primary" => { "adapter" => "sqlite3", "database" => "db/from_hash.sqlite3" } }
      )

      assert_instance_of ActiveRecord::DatabaseConfigurations::UrlConfig, configurations.configs_for(env_name: env_name, name: "primary", include_hidden: true)
      assert_equal "/tmp/env-url.sqlite3", configurations.configs_for(env_name: env_name, name: "primary", include_hidden: true).database
    end
  ensure
    ENV["DATABASE_URL"] = previous_database_url
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

  def test_hash_config_readers_and_mutable_database_copy
    config = ActiveRecord::DatabaseConfigurations::HashConfig.new(
      "production", "primary",
      adapter: :sqlite3,
      database: "db/production.sqlite3",
      host: "localhost",
      socket: "/tmp/sqlite.sock",
      min_threads: "2",
      max_threads: "4",
      query_cache: 42,
      checkout_timeout: "1.5",
      reaping_frequency: nil,
      idle_timeout: 0,
      keepalive: 0,
      schema_cache_path: "tmp/schema-cache.yml",
      migrations_paths: ["db/migrate"],
      replica: true,
      database_tasks: false,
      use_metadata_table: false,
      seeds: false
    )

    assert_equal "sqlite3", config.adapter
    assert_equal "db/production.sqlite3", config.database
    assert_equal "localhost", config.host
    assert_equal "/tmp/sqlite.sock", config.socket
    assert_equal 2, config.min_threads
    assert_equal 4, config.max_threads
    assert_equal 16, config.max_queue
    assert_equal 42, config.query_cache
    assert_equal 1.5, config.checkout_timeout
    assert_nil config.reaping_frequency
    assert_nil config.idle_timeout
    assert_nil config.keepalive
    assert_equal "tmp/schema-cache.yml", config.schema_cache_path
    assert_equal "tmp/schema-cache.yml", config.lazy_schema_cache_path
    assert_equal ["db/migrate"], config.migrations_paths
    assert_predicate config, :replica?
    assert_not_predicate config, :database_tasks?
    assert_not_predicate config, :use_metadata_table?
    assert_not_predicate config, :seeds?

    config._database = "db/renamed.sqlite3"
    assert_equal "db/renamed.sqlite3", config.database
    assert config.configuration_hash.frozen?
  end

  def test_hash_config_defaults_and_boundary_values
    primary = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", adapter: nil, database: "db/primary.sqlite3")
    secondary = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "animals", adapter: "sqlite3", database: "db/animals.sqlite3", pool: -1, max_age: "30")
    capped = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "capped", adapter: "sqlite3", database: "db/capped.sqlite3", max_connections: "7")
    uncapped = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "uncapped", adapter: "sqlite3", database: "db/uncapped.sqlite3", max_connections: nil)

    assert_nil primary.adapter
    assert_equal 5, primary.max_connections
    assert_equal 0, primary.min_connections
    assert_equal 5, primary.max_threads
    assert_equal 20, primary.max_queue
    assert_equal 5.0, primary.checkout_timeout
    assert_equal 300.0, primary.idle_timeout
    assert_equal 600.0, primary.keepalive
    assert_equal Float::INFINITY, primary.max_age
    assert_equal 20.0, primary.reaping_frequency
    assert_equal "db/schema_cache.yml", primary.default_schema_cache_path
    assert_equal "db/schema_cache.yml", primary.lazy_schema_cache_path
    assert_predicate primary, :database_tasks?
    assert_predicate primary, :use_metadata_table?

    assert_nil secondary.max_connections
    assert_equal 5, secondary.max_threads
    assert_equal 30, secondary.max_age
    assert_equal "custom/animals_schema_cache.yml", secondary.default_schema_cache_path("custom")
    assert_equal 7, capped.max_connections
    assert_nil uncapped.max_connections
  end

  def test_hash_config_schema_dump_and_schema_format_contracts
    previous_schema_format = ActiveRecord.schema_format
    ActiveRecord.schema_format = :ruby

    explicit = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "animals", adapter: "sqlite3", database: "db/animals.sqlite3", schema_dump: "animals_dump.rb")
    disabled = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "animals", adapter: "sqlite3", database: "db/animals.sqlite3", schema_dump: false)
    primary = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", adapter: "sqlite3", database: "db/primary.sqlite3")
    secondary_sql = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "animals", adapter: "sqlite3", database: "db/animals.sqlite3", schema_format: :sql)
    invalid = ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "animals", adapter: "sqlite3", database: "db/animals.sqlite3", schema_format: :xml)

    assert_equal "animals_dump.rb", explicit.schema_dump
    assert_nil disabled.schema_dump
    assert_equal :ruby, primary.schema_format
    assert_equal "schema.rb", primary.schema_dump
    assert_equal :sql, secondary_sql.schema_format
    assert_equal "animals_structure.sql", secondary_sql.schema_dump
    assert_nil primary.send(:schema_file_type, :unknown)
    assert_raises(RuntimeError, match: /Invalid schema format/) { invalid.schema_format }
  ensure
    ActiveRecord.schema_format = previous_schema_format
  end

  def test_hash_config_validation_rejects_ambiguous_pool_settings
    assert_raises(RuntimeError, match: /Ambiguous configuration: 'pool'/) do
      ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", adapter: "sqlite3", database: "db/primary.sqlite3", pool: 5, max_connections: 6)
    end

    assert_nothing_raised do
      ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", adapter: "sqlite3", database: "db/primary.sqlite3", pool: 5, max_connections: 5)
    end

    assert_raises(RuntimeError, match: /when setting 'min_connections'/) do
      ActiveRecord::DatabaseConfigurations::HashConfig.new("production", "primary", adapter: "sqlite3", database: "db/primary.sqlite3", pool: 5, min_connections: 1)
    end
  end

  def test_url_config_initializes_from_database_url_and_casts_special_values
    config = ActiveRecord::DatabaseConfigurations::UrlConfig.new(
      "production", "primary",
      "postgres://user:secret@example.com/app?query_cache=12&replica=false&database_tasks=true&schema_dump=false",
      adapter: "sqlite3", database: "fallback"
    )

    assert_equal "postgres://user:secret@example.com/app?query_cache=12&replica=false&database_tasks=true&schema_dump=false", config.url
    assert_equal "postgresql", config.adapter
    assert_equal "app", config.database
    assert_equal "example.com", config.host
    assert_equal "user", config.configuration_hash[:username]
    assert_equal "secret", config.configuration_hash[:password]
    assert_equal 12, config.query_cache
    assert_not_predicate config, :replica?
    assert_predicate config, :database_tasks?
    assert_nil config.schema_dump
    assert config.configuration_hash.frozen?
  end

  def test_url_config_preserves_non_database_urls_and_boolean_query_cache
    jdbc_config = ActiveRecord::DatabaseConfigurations::UrlConfig.new("production", "primary", "jdbc:postgresql://example.com/app", adapter: "postgresql", query_cache: "false")
    http_config = ActiveRecord::DatabaseConfigurations::UrlConfig.new("production", "primary", "https://example.com/database", adapter: "postgresql", replica: "true", database_tasks: "false")

    assert_equal "jdbc:postgresql://example.com/app", jdbc_config.configuration_hash[:url]
    assert_equal false, jdbc_config.query_cache
    assert_equal "https://example.com/database", http_config.configuration_hash[:url]
    assert_predicate http_config, :replica?
    assert_not_predicate http_config, :database_tasks?
  end
end
