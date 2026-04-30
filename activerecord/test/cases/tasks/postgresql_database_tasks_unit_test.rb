# frozen_string_literal: true

require "cases/helper"
require "active_record/tasks/postgresql_database_tasks"

module ActiveRecord
  module Tasks
    class PostgreSQLDatabaseTasksUnitTest < ActiveRecord::TestCase
      DBConfig = Struct.new(:database, :host, :configuration_hash, keyword_init: true)

      class FakeConnection
        attr_reader :calls
        attr_accessor :data_sources, :schema_search_path

        def initialize
          @calls = []
          @data_sources = []
          @schema_search_path = "public"
        end

        def create_database(database, options)
          calls << [:create_database, database, options]
        end

        def drop_database(database)
          calls << [:drop_database, database]
        end
      end

      def db_config(configuration_hash = nil, host: "db.example.test", **options)
        configuration_hash = (configuration_hash || {}).merge(options)
        DBConfig.new(
          database: "app_db",
          host: host,
          configuration_hash: { adapter: "postgresql", database: "app_db" }.merge(configuration_hash)
        )
      end

      def build_task(configuration_hash = nil, host: "db.example.test", **options)
        ActiveRecord::Tasks::PostgreSQLDatabaseTasks.new(db_config(configuration_hash, host: host, **options))
      end

      def test_create_uses_public_schema_connection_and_configured_encoding_then_restores_connection
        connection = FakeConnection.new
        task = build_task(encoding: "unicode")
        established = []
        task.define_singleton_method(:establish_connection) { |config = task.send(:db_config)| established << config }
        task.define_singleton_method(:connection) { connection }

        task.create
        task.create(true)

        assert_equal({ adapter: "postgresql", database: "postgres", encoding: "unicode", schema_search_path: "public" }, established[0])
        assert_equal task.send(:db_config), established[1]
        assert_equal task.send(:db_config), established[2]
        assert_equal [
          [:create_database, "app_db", { adapter: "postgresql", database: "app_db", encoding: "unicode" }],
          [:create_database, "app_db", { adapter: "postgresql", database: "app_db", encoding: "unicode" }]
        ], connection.calls
      end

      def test_create_uses_default_encoding_when_not_configured
        connection = FakeConnection.new
        task = build_task
        task.define_singleton_method(:establish_connection) { |_config = nil| }
        task.define_singleton_method(:connection) { connection }

        task.create

        assert_equal ActiveRecord::Tasks::PostgreSQLDatabaseTasks::DEFAULT_ENCODING, connection.calls.first.last[:encoding]
      end

      def test_drop_connects_to_public_schema_and_drops_database
        connection = FakeConnection.new
        task = build_task
        established = []
        task.define_singleton_method(:establish_connection) { |config = task.send(:db_config)| established << config }
        task.define_singleton_method(:connection) { connection }

        task.drop

        assert_equal({ adapter: "postgresql", database: "postgres", schema_search_path: "public" }, established.first)
        assert_equal [[:drop_database, "app_db"]], connection.calls
      end

      def test_purge_clears_connections_then_drops_and_creates_without_reconnecting_to_public_schema_twice
        task = build_task
        calls = []
        handler = Object.new
        handler.define_singleton_method(:clear_active_connections!) { |scope| calls << [:clear, scope] }
        task.define_singleton_method(:drop) { calls << :drop }
        task.define_singleton_method(:create) { |already_established| calls << [:create, already_established] }

        ActiveRecord::Base.stub(:connection_handler, handler) do
          task.purge
        end

        assert_equal [[:clear, :all], :drop, [:create, true]], calls
      end

      def test_structure_dump_uses_schema_search_path_and_ignore_tables
        task = build_task(schema_search_path: "public, audit")
        connection = FakeConnection.new
        connection.data_sources = ["schema_migrations", "users", "audit_logs"]
        connection.schema_search_path = "public,audit"
        task.define_singleton_method(:connection) { connection }
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args| commands << [cmd, args] }
        task.define_singleton_method(:remove_sql_header_comments) { |filename| File.write(filename, "CREATE TABLE users();\n") }
        original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        original_dump_schemas = ActiveRecord.dump_schemas
        ActiveRecord::SchemaDumper.ignore_tables = ["schema_migrations", /audit/]
        ActiveRecord.dump_schemas = :schema_search_path
        file = Tempfile.new("structure")
        file.close

        task.structure_dump(file.path, ["--verbose"])

        assert_equal "pg_dump", commands.first.first
        args = commands.first.last
        assert_includes args, "--schema-only"
        assert_includes args, "--no-privileges"
        assert_includes args, "--no-owner"
        assert_includes args, "--file"
        assert_includes args, file.path
        assert_includes args, "--verbose"
        assert_includes args, "--schema=public"
        assert_includes args, "--schema=audit"
        assert_includes args, "-T"
        assert_includes args, "schema_migrations"
        assert_includes args, "audit_logs"
        assert_equal "app_db", args.last
        assert_includes File.read(file.path), "SET search_path TO public,audit;"
      ensure
        ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
        ActiveRecord.dump_schemas = original_dump_schemas
        file.unlink if file
      end

      def test_structure_dump_all_schemas_and_string_schema_without_ignored_tables_or_extra_flags
        task = build_task
        connection = FakeConnection.new
        connection.schema_search_path = "custom"
        task.define_singleton_method(:connection) { connection }
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args| commands << [cmd, args] }
        task.define_singleton_method(:remove_sql_header_comments) { |filename| File.write(filename, "") }
        original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        original_dump_schemas = ActiveRecord.dump_schemas
        ActiveRecord::SchemaDumper.ignore_tables = []
        file = Tempfile.new("structure")
        file.close

        ActiveRecord.dump_schemas = :all
        task.structure_dump(file.path, nil)
        assert_not commands.last.last.any? { |arg| arg.to_s.start_with?("--schema=") }
        assert_not_includes commands.last.last, "-T"

        ActiveRecord.dump_schemas = "analytics, reporting"
        task.structure_dump(file.path, nil)
        assert_includes commands.last.last, "--schema=analytics"
        assert_includes commands.last.last, "--schema=reporting"

        ActiveRecord.dump_schemas = nil
        task.structure_dump(file.path, nil)
        assert_not commands.last.last.any? { |arg| arg.to_s.start_with?("--schema=") }
      ensure
        ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
        ActiveRecord.dump_schemas = original_dump_schemas
        file.unlink if file
      end

      def test_structure_load_builds_psql_command
        task = build_task
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args| commands << [cmd, args] }

        task.structure_load("/tmp/structure.sql", ["--single-transaction"])
        task.structure_load("/tmp/structure.sql", nil)

        assert_equal "psql", commands[0].first
        assert_equal ["--set", "ON_ERROR_STOP=1", "--quiet", "--no-psqlrc", "--output", File::NULL, "--single-transaction", "--file", "/tmp/structure.sql", "app_db"], commands[0].last
        assert_equal ["--set", "ON_ERROR_STOP=1", "--quiet", "--no-psqlrc", "--output", File::NULL, "--file", "/tmp/structure.sql", "app_db"], commands[1].last
      end

      def test_psql_env_maps_connection_settings_and_run_cmd_uses_environment
        task = build_task(
          port: 5433, password: "secret", username: "deploy", sslmode: "verify-full",
          sslcert: "client.crt", sslkey: "client.key", sslrootcert: "root.crt"
        )

        assert_equal({
          "PGHOST" => "db.example.test",
          "PGPORT" => "5433",
          "PGPASSWORD" => "secret",
          "PGUSER" => "deploy",
          "PGSSLMODE" => "verify-full",
          "PGSSLCERT" => "client.crt",
          "PGSSLKEY" => "client.key",
          "PGSSLROOTCERT" => "root.crt"
        }, task.send(:psql_env))
        assert_equal({}, build_task(host: nil).send(:psql_env))

        system_calls = []
        Kernel.stub(:system, ->(*args, **opts) { system_calls << [args, opts]; true }) do
          task.send(:run_cmd, "psql", "--version")
        end
        assert_equal task.send(:psql_env), system_calls.first.first[0]
        assert_equal ["psql", "--version"], system_calls.first.first[1..]
      end

      def test_run_cmd_raises_when_system_fails
        task = build_task

        Kernel.stub(:system, false) do
          error = assert_raises(RuntimeError) { task.send(:run_cmd, "psql", "--bad") }
          assert_includes error.message, "failed to execute"
          assert_includes error.message, "psql --bad"
        end
      end

      def test_remove_sql_header_comments_removes_leading_comments_blank_lines_and_restrict_blocks
        file = Tempfile.new("structure")
        file.write("-- dumped by pg_dump\n\n\\restrict abc\nCREATE TABLE users();\n-- keep later comment\n\\unrestrict abc\n-- remove after unrestrict\nCREATE TABLE posts();\n")
        file.close

        build_task.send(:remove_sql_header_comments, file.path)

        assert_equal "CREATE TABLE users();\n-- keep later comment\nCREATE TABLE posts();\n", File.read(file.path)
      ensure
        file.unlink if file
      end
    end
  end
end
