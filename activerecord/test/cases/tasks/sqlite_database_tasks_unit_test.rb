# frozen_string_literal: true

require "cases/helper"
require "active_record/tasks/sqlite_database_tasks"

module ActiveRecord
  module Tasks
    class SQLiteDatabaseTasksUnitTest < ActiveRecord::TestCase
      DBConfig = Struct.new(:database, keyword_init: true)

      class FakeConnection
        attr_reader :calls
        attr_accessor :data_sources

        def initialize
          @calls = []
          @data_sources = []
        end

        def connect!
          calls << :connect
        end

        def disconnect!
          calls << :disconnect
        end

        def reconnect!
          calls << :reconnect
        end

        def quote(value)
          "'#{value}'"
        end
      end

      def db_config(database = "db/test.sqlite3")
        DBConfig.new(database: database)
      end

      def build_task(database = "db/test.sqlite3", root: Dir.pwd)
        ActiveRecord::Tasks::SQLiteDatabaseTasks.new(db_config(database), root)
      end

      def test_create_establishes_connection_when_database_file_is_absent
        path = Tempfile.new("sqlite-db")
        database = path.path
        path.close!
        task = build_task(database)
        connection = FakeConnection.new
        established = []
        task.define_singleton_method(:connection) { connection }
        ActiveRecord::Base.stub(:establish_connection, ->(config) { established << config }) do
          task.create
        end

        assert_equal [task.send(:db_config)], established
        assert_equal [:connect], connection.calls
      end

      def test_create_raises_when_database_file_exists
        file = Tempfile.new("sqlite-db")
        file.close

        assert_raises(ActiveRecord::DatabaseAlreadyExists) do
          build_task(file.path).create
        end
      ensure
        file.unlink if file
      end

      def test_drop_removes_database_and_wal_files
        dir = Dir.mktmpdir
        database = File.join(dir, "test.sqlite3")
        File.write(database, "")
        File.write("#{database}-shm", "")
        File.write("#{database}-wal", "")

        build_task(database).drop

        assert_not File.exist?(database)
        assert_not File.exist?("#{database}-shm")
        assert_not File.exist?("#{database}-wal")
      ensure
        FileUtils.rm_rf(dir) if dir
      end

      def test_drop_raises_no_database_error_when_file_is_missing
        error = assert_raises(ActiveRecord::NoDatabaseError) do
          build_task("/tmp/missing-sqlite-unit.sqlite3").drop
        end

        assert_includes error.message, "No such file or directory"
      end

      def test_purge_disconnects_drops_recreates_and_reconnects_even_when_drop_fails
        task = build_task
        connection = FakeConnection.new
        calls = []
        task.define_singleton_method(:connection) { connection }
        task.define_singleton_method(:drop) { calls << :drop; raise ActiveRecord::NoDatabaseError.new }
        task.define_singleton_method(:create) { calls << :create }

        task.purge

        assert_equal [:drop, :create], calls
        assert_equal [:disconnect, :reconnect], connection.calls
      end

      def test_structure_dump_uses_schema_command_without_ignored_tables
        task = build_task("db.sqlite3")
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args, **opts| commands << [cmd, args, opts] }
        original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        ActiveRecord::SchemaDumper.ignore_tables = []

        task.structure_dump("structure.sql", ["-readonly"])

        assert_equal "sqlite3", commands.first[0]
        assert_equal ["-readonly", "db.sqlite3", ".schema --nosys"], commands.first[1]
        assert_equal({ out: "structure.sql" }, commands.first[2])
      ensure
        ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
      end

      def test_structure_dump_filters_ignored_tables_against_data_sources
        task = build_task("db.sqlite3")
        connection = FakeConnection.new
        connection.data_sources = ["schema_migrations", "users", "internal_metadata"]
        task.define_singleton_method(:connection) { connection }
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args, **opts| commands << [cmd, args, opts] }
        original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        ActiveRecord::SchemaDumper.ignore_tables = ["schema_migrations", /internal/]

        task.structure_dump("structure.sql", nil)

        sql = commands.first[1].last
        assert_equal "sqlite3", commands.first[0]
        assert_equal "db.sqlite3", commands.first[1].first
        assert_includes sql, "SELECT sql || ';' FROM sqlite_master"
        assert_includes sql, "tbl_name NOT IN ('schema_migrations', 'internal_metadata')"
        assert_includes sql, "ORDER BY tbl_name, type DESC, name"
      ensure
        ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
      end

      def test_structure_load_passes_flags_database_and_input_file
        task = build_task("db.sqlite3")
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args, **opts| commands << [cmd, args, opts] }

        task.structure_load("structure.sql", ["-readonly"])
        task.structure_load("structure.sql", nil)

        assert_equal ["sqlite3", ["-readonly", "db.sqlite3"], { in: "structure.sql" }], commands[0]
        assert_equal ["sqlite3", ["db.sqlite3"], { in: "structure.sql" }], commands[1]
      end

      def test_check_current_protected_environment_ignores_readonly_sqlite_errors_only
        task = build_task
        readonly = ActiveRecord::StatementInvalid.new("readonly")
        readonly.define_singleton_method(:cause) { SQLite3::ReadOnlyException.new("readonly") }
        other = ActiveRecord::StatementInvalid.new("other")
        other.define_singleton_method(:cause) { RuntimeError.new("other") }

        current_error = readonly
        task.define_singleton_method(:with_temporary_pool) { |_db_config, _migration_class| raise current_error }
        assert_nil task.check_current_protected_environment!(db_config, ActiveRecord::Base)

        current_error = other
        assert_raises(ActiveRecord::StatementInvalid) do
          task.check_current_protected_environment!(db_config, ActiveRecord::Base)
        end
      end
    end
  end
end
