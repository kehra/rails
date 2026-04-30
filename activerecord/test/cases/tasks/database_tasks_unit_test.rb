# frozen_string_literal: true

require "cases/helper"
require "active_record/tasks/database_tasks"
require "ostruct"

module ActiveRecord
  module Tasks
    class DatabaseTasksUnitTest < ActiveRecord::TestCase
      DBConfig = Struct.new(:adapter, :database, :name, :env_name, :host, :schema_format, :schema_dump_value, :seeds_value, :configuration_hash, keyword_init: true) do
        def schema_dump(format = schema_format)
          schema_dump_value.respond_to?(:call) ? schema_dump_value.call(format) : schema_dump_value
        end

        def seeds? = seeds_value
        def primary? = name == "primary"
        def schema_cache_path = nil
        def default_schema_cache_path(db_dir) = File.join(db_dir, "schema_cache.yml")
      end

      class RecordingAdapter
        attr_reader :config, :arguments, :calls
        class << self
          attr_accessor :use_database_configurations

          def using_database_configurations?
            use_database_configurations
          end
        end

        def initialize(config, *arguments)
          @config = config
          @arguments = arguments
          @calls = []
        end

        def create = calls << :create
        def drop = calls << :drop
        def purge = calls << :purge
        def charset = "utf8"
        def collation = "utf8_unicode_ci"
        def structure_dump(filename, flags) = calls << [:structure_dump, filename, flags]
        def structure_load(filename, flags) = calls << [:structure_load, filename, flags]
        def check_current_protected_environment!(*args) = calls << [:check_current_protected_environment, args]
      end

      def setup
        @tasks = ActiveRecord::Tasks::DatabaseTasks
        @stdout, $stdout = $stdout, StringIO.new
        @stderr, $stderr = $stderr, StringIO.new
        @old_dump_flags = @tasks.structure_dump_flags
        @old_load_flags = @tasks.structure_load_flags
        @old_schema = ENV.delete("SCHEMA")
        @old_verbose = ENV.delete("VERBOSE")
      end

      def teardown
        $stdout = @stdout
        $stderr = @stderr
        @tasks.structure_dump_flags = @old_dump_flags
        @tasks.structure_load_flags = @old_load_flags
        ENV["SCHEMA"] = @old_schema if @old_schema
        ENV["VERBOSE"] = @old_verbose if @old_verbose
      end

      def db_config(**options)
        DBConfig.new({ adapter: "unit", database: "unit_db", name: "primary", env_name: "test", host: "localhost", schema_format: :ruby, schema_dump_value: "schema.rb", seeds_value: false, configuration_hash: { database: "unit_db" } }.merge(options))
      end

      def with_registered_adapter(adapter = RecordingAdapter)
        old_tasks = @tasks.instance_variable_get(:@tasks).dup
        @tasks.register_task(/unit/, adapter)
        yield
      ensure
        @tasks.instance_variable_set(:@tasks, old_tasks)
        RecordingAdapter.use_database_configurations = nil
      end

      def test_database_adapter_for_uses_configuration_hash_for_legacy_tasks
        config = db_config(configuration_hash: { adapter: "unit", database: "legacy" })

        with_registered_adapter do
          adapter = @tasks.send(:database_adapter_for, config, :extra)

          assert_equal({ adapter: "unit", database: "legacy" }, adapter.config)
          assert_equal [:extra], adapter.arguments
        end
      end

      def test_database_adapter_for_can_pass_database_config_objects
        config = db_config
        RecordingAdapter.use_database_configurations = true

        with_registered_adapter do
          adapter = @tasks.send(:database_adapter_for, config)

          assert_same config, adapter.config
        end
      end

      def test_class_for_adapter_raises_for_unknown_adapters
        error = assert_raises(ActiveRecord::Tasks::DatabaseNotSupported) do
          @tasks.send(:class_for_adapter, "unknown")
        end

        assert_match "Rake tasks not supported by 'unknown' adapter", error.message
      end

      def test_structure_flags_accept_hash_or_plain_values
        @tasks.structure_dump_flags = { unit: ["--dump"] }
        @tasks.structure_load_flags = "--load"

        assert_equal ["--dump"], @tasks.send(:structure_dump_flags_for, "unit")
        assert_equal "--load", @tasks.send(:structure_load_flags_for, "unit")
      end

      def test_create_reports_already_existing_database_when_verbose
        config = db_config
        adapter = Object.new
        def adapter.create = raise ActiveRecord::DatabaseAlreadyExists.new("exists")

        @tasks.stub(:resolve_configuration, config) do
          @tasks.stub(:database_adapter_for, adapter) do
            @tasks.create(config)
          end
        end

        assert_includes $stderr.string, "Database 'unit_db' already exists"
      end

      def test_create_reraises_unknown_errors_with_context
        config = db_config
        adapter = Object.new
        def adapter.create = raise RuntimeError, "boom"

        assert_raises(RuntimeError) do
          @tasks.stub(:resolve_configuration, config) do
            @tasks.stub(:database_adapter_for, adapter) do
              @tasks.create(config)
            end
          end
        end

        assert_includes $stderr.string, "Couldn't create 'unit_db' database"
      end

      def test_drop_handles_missing_database_and_reraises_unknown_errors
        missing = Object.new
        def missing.drop = raise ActiveRecord::NoDatabaseError.new
        config = db_config

        @tasks.stub(:resolve_configuration, config) do
          @tasks.stub(:database_adapter_for, missing) { @tasks.drop(config) }
        end
        assert_includes $stderr.string, "Database 'unit_db' does not exist"

        broken = Object.new
        def broken.drop = raise RuntimeError, "boom"
        assert_raises(RuntimeError) do
          @tasks.stub(:resolve_configuration, config) do
            @tasks.stub(:database_adapter_for, broken) { @tasks.drop(config) }
          end
        end
        assert_includes $stderr.string, "Couldn't drop database 'unit_db'"
      end

      def test_target_version_and_validation
        ENV["VERSION"] = "123"
        assert_equal 123, @tasks.target_version
        assert_nil @tasks.check_target_version

        ENV["VERSION"] = "abc"
        assert_raises(RuntimeError) { @tasks.check_target_version }
      ensure
        ENV.delete("VERSION")
      end

      def test_schema_dump_path_handles_env_absolute_db_dir_and_relative_paths
        config = db_config(schema_dump_value: "schema.rb")
        @tasks.db_dir = "/app/db"

        ENV["SCHEMA"] = "/tmp/custom_schema.rb"
        assert_equal "/tmp/custom_schema.rb", @tasks.schema_dump_path(config)
        ENV.delete("SCHEMA")

        assert_equal "/absolute/schema.rb", @tasks.schema_dump_path(db_config(schema_dump_value: "/absolute/schema.rb"))
        assert_equal "/app/db/schema.rb", @tasks.schema_dump_path(config)
        assert_nil @tasks.schema_dump_path(db_config(schema_dump_value: nil))
      end

      def test_cache_dump_filename_precedence_and_schema_cache_helpers
        config = db_config
        cache = Object.new
        dumped_to = []
        cache.define_singleton_method(:dump_to) { |filename| dumped_to << filename }
        conn = OpenStruct.new(schema_cache: cache)
        file = Tempfile.new("schema-cache")
        file.close

        assert_equal "explicit.yml", @tasks.cache_dump_filename(config, schema_cache_path: "explicit.yml")
        @tasks.dump_schema_cache(conn, "cache.yml")
        assert_equal ["cache.yml"], dumped_to
        @tasks.clear_schema_cache(file.path)
        assert_not File.exist?(file.path)
      end

      def test_check_schema_sha1_requires_enabled_metadata_table_and_matching_digest
        file = Tempfile.new("schema")
        file.write("abc")
        file.close
        metadata = { schema_sha1: OpenSSL::Digest::SHA1.hexdigest("abc") }
        metadata.define_singleton_method(:enabled?) { true }
        metadata.define_singleton_method(:table_exists?) { true }
        pool = OpenStruct.new(internal_metadata: metadata)

        assert @tasks.send(:check_schema_sha1, pool, file.path)

        metadata.define_singleton_method(:enabled?) { false }
        assert_not @tasks.send(:check_schema_sha1, pool, file.path)
        metadata.define_singleton_method(:enabled?) { true }
        metadata.define_singleton_method(:table_exists?) { false }
        assert_not @tasks.send(:check_schema_sha1, pool, file.path)
      ensure
        file.unlink if file
      end

      def test_load_seed_requires_loader_and_invokes_it
        loader = Minitest::Mock.new
        loader.expect(:load_seed, nil)
        @tasks.seed_loader = loader
        @tasks.load_seed
        loader.verify

        @tasks.stub(:seed_loader, nil) do
          assert_raises(RuntimeError) { @tasks.load_seed }
        end
      ensure
        @tasks.seed_loader = nil
        @tasks.remove_instance_variable(:@seed_loader) if @tasks.instance_variable_defined?(:@seed_loader)
      end

      def test_each_current_environment_includes_test_for_development_unless_skipped
        yielded = []
        @tasks.send(:each_current_environment, "development") { |env| yielded << env }
        assert_equal ["development", "test"], yielded

        ENV["SKIP_TEST_DATABASE"] = "1"
        yielded = []
        @tasks.send(:each_current_environment, "development") { |env| yielded << env }
        assert_equal ["development"], yielded
      ensure
        ENV.delete("SKIP_TEST_DATABASE")
        ENV.delete("DATABASE_URL")
      end

      def test_local_database_detects_blank_and_loopback_hosts
        assert @tasks.send(:local_database?, db_config(host: nil))
        assert @tasks.send(:local_database?, db_config(host: "127.0.0.1"))
        assert_not @tasks.send(:local_database?, db_config(host: "db.example.com"))
      end

      def test_default_paths_delegate_to_rails_and_fixtures_path_honors_env
        app = OpenStruct.new(
          config: OpenStruct.new(paths: { "db" => ["custom-db"] }),
          paths: { "db/migrate" => ["migrate/one", "migrate/two"] }
        )
        Rails.singleton_class.define_method(:application) { app } unless Rails.respond_to?(:application)
        Rails.singleton_class.define_method(:root) { "/rails-root" } unless Rails.respond_to?(:root)
        Rails.singleton_class.define_method(:env) { "production" } unless Rails.respond_to?(:env)

        Rails.stub(:application, app) do
          Rails.stub(:root, "/rails-root") do
            Rails.stub(:env, "production") do
              @tasks.remove_instance_variable(:@db_dir) if @tasks.instance_variable_defined?(:@db_dir)
              @tasks.remove_instance_variable(:@migrations_paths) if @tasks.instance_variable_defined?(:@migrations_paths)
              @tasks.remove_instance_variable(:@fixtures_path) if @tasks.instance_variable_defined?(:@fixtures_path)
              @tasks.remove_instance_variable(:@root) if @tasks.instance_variable_defined?(:@root)
              @tasks.remove_instance_variable(:@env) if @tasks.instance_variable_defined?(:@env)
              @tasks.remove_instance_variable(:@name) if @tasks.instance_variable_defined?(:@name)

              assert_equal "custom-db", @tasks.db_dir
              assert_equal ["migrate/one", "migrate/two"], @tasks.migrations_paths
              assert_equal "/rails-root", @tasks.root
              assert_equal "production", @tasks.env
              assert_equal "primary", @tasks.name
              assert_equal File.join("/rails-root", "test", "fixtures"), @tasks.fixtures_path

              @tasks.remove_instance_variable(:@fixtures_path)
              ENV["FIXTURES_PATH"] = "spec/fixtures"
              assert_equal File.join("/rails-root", "spec", "fixtures"), @tasks.fixtures_path
            end
          end
        end
      ensure
        ENV.delete("FIXTURES_PATH")
      end

      def test_setup_initial_database_yaml_and_for_each_delegate_to_rails_configuration
        app = OpenStruct.new(config: OpenStruct.new(load_database_yaml: { "test" => { "primary" => {} } }))
        Rails.singleton_class.define_method(:application) { app } unless Rails.respond_to?(:application)
        Rails.singleton_class.define_method(:env) { "test" } unless Rails.respond_to?(:env)

        Rails.stub(:application, app) do
          assert_equal({ "test" => { "primary" => {} } }, @tasks.setup_initial_database_yaml)
        end

        names = []
        databases = {
          "test" => {
            "primary" => { "adapter" => "sqlite3", "database" => "one" },
            "animals" => { "adapter" => "sqlite3", "database" => "two" }
          }
        }
        Rails.stub(:env, "test") do
          @tasks.for_each(databases) { |name| names << name }
        end
        assert_equal ["primary", "animals"], names
      end

      def test_check_protected_environments_can_be_disabled_or_delegated
        config = db_config
        adapter = Minitest::Mock.new
        adapter.expect(:check_current_protected_environment!, nil, [config, ActiveRecord::Base])

        ENV["DISABLE_DATABASE_ENVIRONMENT_CHECK"] = "1"
        @tasks.stub(:configs_for, [config]) do
          @tasks.check_protected_environments!("production")
        end

        ENV.delete("DISABLE_DATABASE_ENVIRONMENT_CHECK")
        @tasks.stub(:configs_for, [config]) do
          @tasks.stub(:database_adapter_for, adapter) do
            @tasks.check_protected_environments!("production")
          end
        end
        adapter.verify
        assert true
      ensure
        ENV.delete("DISABLE_DATABASE_ENVIRONMENT_CHECK")
      end

      def test_raise_for_multi_db_lists_namespaced_tasks
        configs = [db_config(name: "primary"), db_config(name: "animals")]

        @tasks.stub(:configs_for, configs) do
          error = assert_raises(RuntimeError) { @tasks.raise_for_multi_db("test", command: "db:migrate") }
          assert_includes error.message, "db:migrate:primary"
          assert_includes error.message, "db:migrate:animals"
        end

        @tasks.stub(:configs_for, [configs.first]) do
          assert_nil @tasks.raise_for_multi_db("test", command: "db:migrate")
        end
      end

      def test_create_all_and_current_restore_migration_connection
        config = db_config
        migration_connection = OpenStruct.new(pool: OpenStruct.new(db_config: config))
        migration_class = Minitest::Mock.new
        migration_class.expect(:establish_connection, nil, [config])
        migration_class.expect(:establish_connection, nil, [:test])

        @tasks.stub(:migration_connection, migration_connection) do
          @tasks.stub(:each_local_configuration, ->(&block) { block.call(config) }) do
            @tasks.stub(:create, nil) do
              @tasks.stub(:migration_class, migration_class) do
                @tasks.create_all
                @tasks.stub(:each_current_configuration, ->(_env, _name = nil, &block) { block.call(config) }) do
                  @tasks.create_current("test")
                end
              end
            end
          end
        end
        migration_class.verify
        assert true
      end

      def test_truncate_all_delegates_to_current_configurations
        config = db_config
        called = []
        @tasks.stub(:configs_for, [config]) do
          @tasks.stub(:truncate_tables, ->(db_config) { called << db_config }) do
            @tasks.truncate_all("test")
          end
        end
        assert_equal [config], called
      end

      def test_db_configs_with_versions_groups_pending_versions_and_honors_target_version
        config = db_config(name: "primary")
        pool = OpenStruct.new(db_config: config, migration_context: OpenStruct.new(pending_migration_versions: [1, 2]))

        ENV["VERSION"] = "2"
        @tasks.stub(:with_temporary_pool_for_each, ->(env:, name: nil, clobber: false, &block) { block.call(pool) }) do
          assert_equal({ 2 => [config] }, @tasks.db_configs_with_versions("test"))
        end
      ensure
        ENV.delete("VERSION")
      end

      def test_migrate_filters_by_scope_or_explicit_version_and_clears_schema_cache
        migrations = [OpenStruct.new(scope: "animals", version: 10), OpenStruct.new(scope: "primary", version: 20)]
        selected = []
        context = Object.new
        context.define_singleton_method(:migrate) do |_target, &block|
          selected = migrations.select { |migration| block.call(migration) }
          selected
        end
        schema_cache = Minitest::Mock.new
        schema_cache.expect(:clear!, nil)
        pool = OpenStruct.new(db_config: db_config, migration_context: context, schema_cache: schema_cache)

        ENV["SCOPE"] = "animals"
        @tasks.stub(:migration_connection_pool, pool) do
          @tasks.stub(:initialize_database, nil) do
            @tasks.migrate(nil, skip_initialize: true)
          end
        end
        assert_equal [10], selected.map(&:version)
        schema_cache.verify

        selected.clear
        schema_cache = Minitest::Mock.new
        schema_cache.expect(:clear!, nil)
        pool.schema_cache = schema_cache
        ENV.delete("SCOPE")
        @tasks.stub(:migration_connection_pool, pool) do
          @tasks.stub(:initialize_database, nil) do
            @tasks.migrate(20, skip_initialize: true)
          end
        end
        assert_equal [20], selected.map(&:version)
      ensure
        ENV.delete("SCOPE")
      end

      def test_migrate_status_prints_status_or_aborts_without_schema_table
        schema_migration = OpenStruct.new(table_exists?: true)
        context = OpenStruct.new(migrations_status: [["up", "001", "CreateUsers"]])
        pool = OpenStruct.new(schema_migration: schema_migration, db_config: db_config(database: "status_db"), migration_context: context)

        @tasks.stub(:migration_connection_pool, pool) do
          @tasks.migrate_status
        end
        assert_includes $stdout.string, "status_db"
        assert_includes $stdout.string, "CreateUsers"

        pool.schema_migration = OpenStruct.new(table_exists?: false)
        @tasks.stub(:migration_connection_pool, pool) do
          assert_raises(SystemExit) { @tasks.migrate_status }
        end
      end

      def test_each_local_configuration_yields_only_local_databases
        local = db_config(database: "local", host: "localhost")
        remote = db_config(database: "remote", host: "db.example.com")
        no_database = db_config(database: nil)
        yielded = []

        @tasks.stub(:configs_for, [local, remote, no_database]) do
          @tasks.send(:each_local_configuration) { |db_config| yielded << db_config.database }
        end

        assert_equal ["local"], yielded
        assert_includes $stderr.string, "remote is on a remote host"
      end
    end
  end
end
