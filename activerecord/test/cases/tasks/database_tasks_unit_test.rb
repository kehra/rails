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

      def test_prepare_all_initializes_migrates_dumps_and_loads_seed
        config = db_config(name: "primary", seeds_value: true)
        calls = []
        @tasks.stub(:env, "test") do
          @tasks.stub(:each_current_configuration, ->(_env, &block) { block.call(config) }) do
            @tasks.stub(:initialize_database, ->(db_config) { calls << [:initialize, db_config.name]; true }) do
              @tasks.stub(:each_current_environment, ->(_env, &block) { block.call("test") }) do
                @tasks.stub(:db_configs_with_versions, ->(_environment) { { 2 => [config] } }) do
                  @tasks.stub(:with_temporary_pool, ->(db_config, clobber: false, &block) { calls << [:pool, db_config.name, clobber]; block&.call(OpenStruct.new(db_config: db_config)) }) do
                    @tasks.stub(:migrate, ->(version) { calls << [:migrate, version] }) do
                      @tasks.stub(:dump_schema, ->(db_config) { calls << [:dump_schema, db_config.name] }) do
                        @tasks.stub(:load_seed, -> { calls << [:load_seed] }) do
                          ActiveRecord.stub(:dump_schema_after_migration, true) do
                            @tasks.prepare_all
                          end
                        end
                      end
                    end
                  end
                end
              end
            end
          end
        end

        assert_includes calls, [:initialize, "primary"]
        assert_includes calls, [:migrate, 2]
        assert_includes calls, [:dump_schema, "primary"]
        assert_includes calls, [:load_seed]
      end

      def test_prepare_all_skips_schema_dump_and_seed_when_not_needed
        config = db_config(seeds_value: false)
        calls = []
        @tasks.stub(:env, "test") do
          @tasks.stub(:each_current_configuration, ->(_env, &block) { block.call(config) }) do
            @tasks.stub(:initialize_database, false) do
              @tasks.stub(:each_current_environment, ->(_env, &block) { block.call("test") }) do
                @tasks.stub(:db_configs_with_versions, {}) do
                  @tasks.stub(:dump_schema, ->(*) { calls << :dump_schema }) do
                    @tasks.stub(:load_seed, -> { calls << :load_seed }) do
                      ActiveRecord.stub(:dump_schema_after_migration, false) do
                        @tasks.prepare_all
                      end
                    end
                  end
                end
              end
            end
          end
        end
        assert_empty calls
      end

      def test_migrate_all_uses_single_primary_fast_path_or_grouped_multi_db_path
        primary = db_config(name: "primary")
        secondary = db_config(name: "animals")
        configurations = Object.new
        configurations.define_singleton_method(:configs_for) { |env_name:| [primary] }
        calls = []

        ActiveRecord::Base.stub(:configurations, configurations) do
          @tasks.stub(:env, "test") do
            @tasks.stub(:initialize_database, ->(db_config) { calls << [:initialize, db_config.name] }) do
              @tasks.stub(:migrate, ->(skip_initialize:) { calls << [:migrate, skip_initialize] }) do
                @tasks.migrate_all
              end
            end
          end
        end
        assert_includes calls, [:migrate, true]

        configurations.define_singleton_method(:configs_for) { |env_name:| [primary, secondary] }
        calls.clear
        ActiveRecord::Base.stub(:configurations, configurations) do
          @tasks.stub(:env, "test") do
            @tasks.stub(:initialize_database, ->(db_config) { calls << [:initialize, db_config.name] }) do
              @tasks.stub(:db_configs_with_versions, { 7 => [secondary] }) do
                @tasks.stub(:with_temporary_connection, ->(db_config, clobber: false, &block) { calls << [:temporary, db_config.name]; block.call(Object.new) }) do
                  @tasks.stub(:migrate, ->(version, skip_initialize:) { calls << [:migrate, version, skip_initialize] }) do
                    @tasks.migrate_all
                  end
                end
              end
            end
          end
        end
        assert_includes calls, [:temporary, "animals"]
        assert_includes calls, [:migrate, 7, true]
      end

      def test_load_schema_handles_ruby_sql_unknown_format_and_metadata
        config = db_config(env_name: "test", schema_format: :ruby)
        file = Tempfile.new("schema")
        file.write("$database_tasks_unit_loaded = true")
        file.close
        metadata = Minitest::Mock.new
        metadata.expect(:create_table_and_set_flags, nil, ["test", OpenSSL::Digest::SHA1.hexdigest(File.read(file.path))])
        pool = OpenStruct.new(internal_metadata: metadata)

        @tasks.stub(:migration_connection_pool, pool) do
          @tasks.load_schema(config, :ruby, file.path)
        end
        assert $database_tasks_unit_loaded
        metadata.verify

        called = []
        metadata = Object.new
        metadata.define_singleton_method(:create_table_and_set_flags) { |_env, _sha| }
        @tasks.stub(:migration_connection_pool, OpenStruct.new(internal_metadata: metadata)) do
          @tasks.stub(:structure_load, ->(db_config, path) { called << [db_config, path] }) do
            @tasks.load_schema(config, :sql, file.path)
          end
        end
        assert_equal [[config, file.path]], called

        assert_raises(ArgumentError) do
          @tasks.load_schema(config, :xml, file.path)
        end
      ensure
        file.unlink if file
        $database_tasks_unit_loaded = nil
      end

      def test_schema_up_to_date_short_circuits_or_uses_given_pool
        config = db_config(schema_dump_value: nil)
        @tasks.stub(:resolve_configuration, config) do
          assert @tasks.schema_up_to_date?(config)
        end

        file = Tempfile.new("schema")
        file.write("abc")
        file.close
        config = db_config(schema_dump_value: file.path)
        pool = Object.new
        checked = []
        @tasks.stub(:resolve_configuration, config) do
          @tasks.stub(:check_schema_sha1, ->(given_pool, given_file) { checked << [given_pool, given_file]; true }) do
            assert @tasks.schema_up_to_date?(config, nil, file.path, pool: pool)
          end
        end
        assert_equal [[pool, file.path]], checked
      ensure
        file.unlink if file
      end

      def test_reconstruct_from_schema_empties_purges_or_creates_then_loads
        config = db_config(schema_format: :ruby)
        file = Tempfile.new("schema")
        file.close
        calls = []

        @tasks.stub(:with_temporary_pool, ->(db_config, clobber:, &block) { calls << [:pool, clobber]; block.call(Object.new) }) do
          @tasks.stub(:schema_up_to_date?, true) do
            @tasks.stub(:empty_all_tables, ->(db_config) { calls << [:empty, db_config.database] }) do
              @tasks.reconstruct_from_schema(config, file.path)
            end
          end
        end
        assert_includes calls, [:empty, "unit_db"]

        calls.clear
        @tasks.stub(:with_temporary_pool, ->(db_config, clobber:, &block) { block.call(Object.new) }) do
          @tasks.stub(:schema_up_to_date?, false) do
            @tasks.stub(:purge, ->(db_config) { calls << [:purge, db_config.database] }) do
              @tasks.stub(:load_schema, ->(db_config, format, path) { calls << [:load, format, path] }) do
                @tasks.reconstruct_from_schema(config, file.path)
              end
            end
          end
        end
        assert_includes calls, [:purge, "unit_db"]
        assert_includes calls, [:load, :ruby, file.path]

        calls.clear
        @tasks.stub(:with_temporary_pool, ->(db_config, clobber:, &block) { block.call(Object.new.tap { |o| o.define_singleton_method(:raise_no_database) { raise ActiveRecord::NoDatabaseError.new } }) }) do
          @tasks.stub(:schema_up_to_date?, ->(*) { raise ActiveRecord::NoDatabaseError.new }) do
          @tasks.stub(:create, ->(db_config) { calls << [:create, db_config.database] }) do
            @tasks.stub(:load_schema, ->(db_config, format, path) { calls << [:load, format, path] }) do
              @tasks.reconstruct_from_schema(config, file.path)
            end
          end
          end
        end
        assert_includes calls, [:create, "unit_db"]
      ensure
        file.unlink if file
      end

      def test_dump_all_skips_duplicate_schema_paths
        one = db_config(name: "primary", schema_dump_value: "same.rb")
        two = db_config(name: "animals", schema_dump_value: "same.rb")
        configurations = Object.new
        configurations.define_singleton_method(:configs_for) { |env_name:| [one, two] }
        calls = []

        ActiveRecord::Base.stub(:configurations, configurations) do
          @tasks.stub(:env, "test") do
            @tasks.stub(:schema_dump_path, ->(db_config, format = db_config.schema_format) { "db/#{db_config.schema_dump(format)}" }) do
              @tasks.stub(:dump_schema, ->(db_config, format = db_config.schema_format) { calls << [db_config.name, format] }) do
                @tasks.dump_all
              end
            end
          end
        end
        assert_equal [["primary", :ruby]], calls
      end

      def test_dump_schema_writes_ruby_and_sql_formats
        config = db_config(schema_format: :ruby)
        dir = Dir.mktmpdir
        ruby_file = File.join(dir, "schema.rb")
        sql_file = File.join(dir, "structure.sql")
        @tasks.db_dir = dir
        pool = OpenStruct.new(schema_migration: OpenStruct.new(table_exists?: false))
        calls = []

        @tasks.stub(:schema_dump_path, ruby_file) do
          @tasks.stub(:with_temporary_pool, ->(db_config, &block) { block.call(pool) }) do
            ActiveRecord::SchemaDumper.stub(:dump, ->(_pool, file) { file.write("schema") }) do
              @tasks.dump_schema(config, :ruby)
            end
          end
        end
        assert_equal "schema", File.read(ruby_file)

        pool = Object.new
        pool.define_singleton_method(:schema_migration) { OpenStruct.new(table_exists?: true) }
        pool.define_singleton_method(:with_connection) { |&block| block.call(OpenStruct.new(dump_schema_versions: "versions")) }
        @tasks.stub(:schema_dump_path, sql_file) do
          @tasks.stub(:with_temporary_pool, ->(db_config, &block) { block.call(pool) }) do
            @tasks.stub(:structure_dump, ->(db_config, path) { calls << [:structure_dump, path]; File.write(path, "sql\n") }) do
              @tasks.dump_schema(config, :sql)
            end
          end
        end
        assert_includes calls, [:structure_dump, sql_file]
        assert_includes File.read(sql_file), "versions"
      ensure
        FileUtils.rm_rf(dir) if dir
      end

      def test_empty_truncate_and_load_schema_current_use_temporary_connections
        config = db_config(schema_format: :sql)
        conn = Object.new
        conn.define_singleton_method(:tables) { ["users", "posts"] }
        calls = []
        conn.define_singleton_method(:empty_all_tables) { calls << :empty }
        conn.define_singleton_method(:truncate_tables) { |*tables| calls << [:truncate, tables] }

        @tasks.stub(:with_temporary_connection, ->(db_config, clobber: false, &block) { block.call(conn) }) do
          @tasks.send(:empty_all_tables, config)
          @tasks.send(:truncate_tables, config)
          @tasks.stub(:each_current_configuration, ->(_environment, &block) { block.call(config) }) do
            @tasks.stub(:load_schema, ->(db_config, format, file) { calls << [:load_schema, format, file] }) do
              @tasks.load_schema_current(nil, "structure.sql", "test")
            end
          end
        end

        assert_includes calls, :empty
        assert_includes calls, [:truncate, ["users", "posts"]]
        assert_includes calls, [:load_schema, :sql, "structure.sql"]
      end

      def test_schema_up_to_date_uses_temporary_pool_when_pool_not_given
        file = Tempfile.new("schema")
        file.write("abc")
        file.close
        config = db_config(schema_dump_value: file.path)
        pool = Object.new
        calls = []

        @tasks.stub(:resolve_configuration, config) do
          @tasks.stub(:with_temporary_pool, ->(db_config, &block) { calls << [:pool, db_config.database]; block.call(pool) }) do
            @tasks.stub(:check_schema_sha1, ->(given_pool, given_file) { calls << [:check, given_pool, given_file]; true }) do
              assert @tasks.schema_up_to_date?(config)
            end
          end
        end

        assert_includes calls, [:pool, "unit_db"]
        assert_includes calls, [:check, pool, file.path]
      ensure
        file.unlink if file
      end

      def test_with_temporary_pool_for_each_and_connection_helpers
        one = db_config(name: "primary")
        two = db_config(name: "animals")
        configurations = Object.new
        configurations.define_singleton_method(:configs_for) do |env_name:, name: nil|
          name ? one : [one, two]
        end
        calls = []

        ActiveRecord::Base.stub(:configurations, configurations) do
          @tasks.stub(:with_temporary_pool, ->(db_config, clobber: false, &block) { calls << [db_config.name, clobber]; block.call(OpenStruct.new(with_connection: "pool")) }) do
            @tasks.with_temporary_pool_for_each(env: "test", name: "primary", clobber: true) { |_pool| calls << :named }
            @tasks.with_temporary_pool_for_each(env: "test") { |_pool| calls << :each }
          end
        end

        assert_includes calls, ["primary", true]
        assert_includes calls, ["animals", false]
        assert_includes calls, :named
        assert_includes calls, :each

        pool = Object.new
        pool.define_singleton_method(:with_connection) { |&block| block.call(:connection) }
        @tasks.stub(:with_temporary_pool, ->(db_config, clobber: false, &block) { block.call(pool) }) do
          assert_equal :connection, @tasks.with_temporary_connection(one, clobber: true) { |conn| conn }
        end
      end

      def test_initialize_database_creates_missing_database_and_loads_existing_schema
        config = db_config
        file = Tempfile.new("schema")
        file.close
        attempts = 0
        schema_migration = Object.new
        schema_migration.define_singleton_method(:table_exists?) do
          attempts += 1
          raise ActiveRecord::NoDatabaseError.new if attempts == 1
          false
        end
        pool = Object.new
        calls = []
        pool.define_singleton_method(:schema_migration) { schema_migration }

        @tasks.stub(:with_temporary_pool, ->(db_config, &block) { block.call(pool) }) do
          @tasks.stub(:migration_connection_pool, pool) do
            @tasks.stub(:create, ->(db_config) { calls << [:create, db_config.database] }) do
              @tasks.stub(:schema_dump_path, file.path) do
                @tasks.stub(:load_schema, ->(db_config) { calls << [:load_schema, db_config.database] }) do
                  assert @tasks.send(:initialize_database, config)
                end
              end
            end
          end
        end

        assert_includes calls, [:create, "unit_db"]
        assert_includes calls, [:load_schema, "unit_db"]

        schema_migration.define_singleton_method(:table_exists?) { true }
        @tasks.stub(:with_temporary_pool, ->(db_config, &block) { block.call(pool) }) do
          @tasks.stub(:migration_connection_pool, pool) do
            assert_not @tasks.send(:initialize_database, config)
          end
        end
      ensure
        file.unlink if file
      end

      def test_remaining_database_tasks_edge_branches
        config = db_config

        @tasks.structure_load_flags = { unit: ["--load"] }
        assert_equal ["--load"], @tasks.send(:structure_load_flags_for, "unit")

        adapter = Object.new
        def adapter.create = raise ActiveRecord::DatabaseAlreadyExists.new("exists")
        ENV["VERBOSE"] = "false"
        @tasks.stub(:resolve_configuration, config) do
          @tasks.stub(:database_adapter_for, adapter) { @tasks.create(config) }
        end
        assert_equal "", $stderr.string
        ENV.delete("VERBOSE")

        names = []
        single_database = { "test" => { "primary" => { "adapter" => "sqlite3", "database" => "one" } } }
        Rails.singleton_class.define_method(:env) { "test" } unless Rails.respond_to?(:env)
        Rails.stub(:env, "test") do
          assert_nil @tasks.for_each(single_database) { |name| names << name }
        end
        assert_empty names

        file = Tempfile.new("schema")
        file.close
        @tasks.stub(:schema_dump_path, nil) do
          assert_nil @tasks.load_schema(config, :ruby, nil)
        end

        calls = []
        @tasks.stub(:schema_dump_path, nil) do
          @tasks.stub(:with_temporary_pool, ->(db_config, clobber:, &block) { block.call(Object.new) }) do
            @tasks.stub(:schema_up_to_date?, true) do
              @tasks.stub(:empty_all_tables, ->(*) { }) do
                @tasks.reconstruct_from_schema(config, nil)
              end
            end
          end
        end
        @tasks.stub(:schema_dump_path, "schema.rb") do
          @tasks.dump_schema(db_config(schema_dump_value: false), :ruby)
        end
        assert_empty calls

        schema_migration = OpenStruct.new(table_exists?: false)
        pool = OpenStruct.new(schema_migration: schema_migration)
        @tasks.stub(:with_temporary_pool, ->(db_config, &block) { block.call(pool) }) do
          @tasks.stub(:migration_connection_pool, pool) do
            @tasks.stub(:schema_dump_path, nil) do
              assert @tasks.send(:initialize_database, config)
            end
          end
        end
      ensure
        ENV.delete("VERBOSE")
        file.unlink if defined?(file) && file
      end

      def test_migrate_reports_empty_scoped_runs
        context = Object.new
        context.define_singleton_method(:migrate) { |_target, &_block| [] }
        pool = OpenStruct.new(db_config: db_config, migration_context: context, schema_cache: OpenStruct.new(clear!: nil))
        messages = []
        ENV["SCOPE"] = "animals"
        ActiveRecord::Migration.singleton_class.define_method(:write) { |message| messages << message } unless ActiveRecord::Migration.respond_to?(:write)
        @tasks.stub(:migration_connection_pool, pool) do
          @tasks.stub(:initialize_database, nil) do
            ActiveRecord::Migration.stub(:write, ->(message) { messages << message }) do
              @tasks.migrate(nil, skip_initialize: true)
            end
          end
        end
        assert_equal ["No migrations ran. (using animals scope)"], messages
      ensure
        ENV.delete("SCOPE")
      end

      def test_each_current_configuration_skips_non_matching_name
        configs = [db_config(name: "primary"), db_config(name: "animals")]
        yielded = []
        @tasks.stub(:each_current_environment, ->(_environment, &block) { block.call("test") }) do
          @tasks.stub(:configs_for, configs) do
            @tasks.send(:each_current_configuration, "test", "animals") { |db_config| yielded << db_config.name }
          end
        end
        assert_equal ["animals"], yielded
      end

      def test_database_tasks_without_rails_constant_return_empty_defaults
        rails = Object.send(:remove_const, :Rails)
        assert_equal({}, @tasks.setup_initial_database_yaml)
        assert_equal({}, @tasks.for_each({}) { flunk("should not yield") })
      ensure
        Object.const_set(:Rails, rails) if rails && !Object.const_defined?(:Rails)
      end

      def test_dump_schema_nil_unknown_format_and_sql_without_versions
        config = db_config(schema_dump_value: nil)
        @tasks.stub(:schema_dump_path, nil) do
          assert_nil @tasks.dump_schema(config, :ruby)
          assert_nil @tasks.dump_schema(db_config(schema_dump_value: "schema.rb"), :ruby)
        end

        dir = Dir.mktmpdir
        @tasks.db_dir = dir
        file = File.join(dir, "structure.sql")
        pool = Object.new
        pool.define_singleton_method(:schema_migration) { OpenStruct.new(table_exists?: false) }
        @tasks.stub(:schema_dump_path, file) do
          @tasks.stub(:with_temporary_pool, ->(_db_config, &block) { block.call(pool) }) do
            @tasks.stub(:structure_dump, ->(_db_config, path) { File.write(path, "sql\n") }) do
              @tasks.dump_schema(db_config(schema_dump_value: "structure.sql"), :sql)
            end
          end
        end
        assert_equal "sql\n", File.read(file)

        @tasks.stub(:schema_dump_path, file) do
          @tasks.stub(:with_temporary_pool, ->(_db_config, &block) { block.call(pool) }) do
            assert_nil @tasks.dump_schema(db_config(schema_dump_value: "schema.xml"), :xml)
          end
        end
        assert_nil @tasks.dump_schema(db_config(schema_dump_value: false), :xml)
      ensure
        FileUtils.rm_rf(dir) if dir
      end

      def test_check_schema_file_message_with_rails_root
        Rails.define_singleton_method(:root) { "/rails-root" } unless Rails.respond_to?(:root)
        error = assert_raises(RuntimeError) do
          Kernel.stub(:abort, ->(message) { raise message }) do
            @tasks.check_schema_file("/tmp/missing-database-tasks-unit-schema")
          end
        end
        assert_includes error.message, "/rails-root/config/application.rb"
      end

      def test_check_schema_file_message_without_rails_root
        had_root = Rails.respond_to?(:root)
        root_method = Rails.method(:root) if had_root
        Rails.singleton_class.remove_method(:root) if had_root
        error = assert_raises(RuntimeError) do
          Kernel.stub(:abort, ->(message) { raise message }) do
            @tasks.check_schema_file("/tmp/missing-database-tasks-unit-schema")
          end
        end
        assert_includes error.message, "doesn't exist yet"
      ensure
        if had_root && !Rails.respond_to?(:root)
          Rails.define_singleton_method(:root) { root_method.call }
        end
      end

      def test_verbose_false_suppresses_create_and_drop_messages
        config = db_config
        adapter = Object.new
        def adapter.create; end
        def adapter.drop; end
        ENV["VERBOSE"] = "false"

        @tasks.stub(:resolve_configuration, config) do
          @tasks.stub(:database_adapter_for, adapter) do
            @tasks.create(config)
            @tasks.drop(config)
          end
        end

        assert_equal "", $stdout.string
      ensure
        ENV.delete("VERBOSE")
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
