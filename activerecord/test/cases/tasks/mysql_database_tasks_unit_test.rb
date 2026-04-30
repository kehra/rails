# frozen_string_literal: true

require "cases/helper"
require "active_record/tasks/mysql_database_tasks"

module ActiveRecord
  module Tasks
    class MySQLDatabaseTasksUnitTest < ActiveRecord::TestCase
      DBConfig = Struct.new(:database, :configuration_hash, keyword_init: true)

      class FakeConnection
        attr_reader :calls
        attr_accessor :data_sources

        def initialize
          @calls = []
          @data_sources = []
        end

        def create_database(database, options)
          calls << [:create_database, database, options]
        end

        def drop_database(database)
          calls << [:drop_database, database]
        end

        def recreate_database(database, options)
          calls << [:recreate_database, database, options]
        end

        def charset
          "utf8mb4"
        end
      end

      def db_config(configuration_hash = {})
        DBConfig.new(database: "app_db", configuration_hash: { adapter: "mysql2", database: "app_db" }.merge(configuration_hash))
      end

      def build_task(configuration_hash = {})
        ActiveRecord::Tasks::MySQLDatabaseTasks.new(db_config(configuration_hash))
      end

      def test_create_and_purge_use_connection_without_database_then_restore
        connection = FakeConnection.new
        task = build_task(encoding: "utf8mb4", collation: "utf8mb4_unicode_ci")
        established = []
        task.define_singleton_method(:establish_connection) { |config = task.send(:db_config)| established << config }
        task.define_singleton_method(:connection) { connection }

        task.create
        task.purge

        assert_equal({ adapter: "mysql2", database: nil, encoding: "utf8mb4", collation: "utf8mb4_unicode_ci" }, established[0])
        assert_equal task.send(:db_config), established[1]
        assert_equal({ adapter: "mysql2", database: nil, encoding: "utf8mb4", collation: "utf8mb4_unicode_ci" }, established[2])
        assert_equal task.send(:db_config), established[3]
        assert_includes connection.calls, [:create_database, "app_db", { charset: "utf8mb4", collation: "utf8mb4_unicode_ci" }]
        assert_includes connection.calls, [:recreate_database, "app_db", { charset: "utf8mb4", collation: "utf8mb4_unicode_ci" }]
      end

      def test_drop_and_charset_use_active_connection
        connection = FakeConnection.new
        task = build_task
        established = []
        task.define_singleton_method(:establish_connection) { |config = task.send(:db_config)| established << config }
        task.define_singleton_method(:connection) { connection }

        task.drop

        assert_equal [task.send(:db_config)], established
        assert_equal [[:drop_database, "app_db"]], connection.calls
        assert_equal "utf8mb4", task.charset
      end

      def test_creation_options_omit_absent_encoding_and_collation
        assert_equal({}, build_task.send(:creation_options))
        assert_equal({ charset: "utf8" }, build_task(encoding: "utf8").send(:creation_options))
        assert_equal({ collation: "utf8_bin" }, build_task(collation: "utf8_bin").send(:creation_options))
      end

      def test_prepare_command_options_maps_mysql_cli_options_and_skips_nil_values
        task = build_task(
          host: "db.example.test", port: 3307, socket: "/tmp/mysql.sock", username: "root",
          password: "secret", encoding: "utf8mb4", sslca: "ca.pem", sslcert: "cert.pem",
          sslcapath: "/certs", sslcipher: "DHE", sslkey: "key.pem", ssl_mode: "VERIFY_IDENTITY"
        )

        assert_equal [
          "--host=db.example.test",
          "--port=3307",
          "--socket=/tmp/mysql.sock",
          "--user=root",
          "--password=secret",
          "--default-character-set=utf8mb4",
          "--ssl-ca=ca.pem",
          "--ssl-cert=cert.pem",
          "--ssl-capath=/certs",
          "--ssl-cipher=DHE",
          "--ssl-key=key.pem",
          "--ssl-mode=VERIFY_IDENTITY"
        ], task.send(:prepare_command_options)

        assert_equal [], build_task(host: nil).send(:prepare_command_options)
      end

      def test_structure_dump_builds_mysqldump_command_with_ignored_tables_and_extra_flags
        task = build_task(host: "localhost", username: "root")
        connection = FakeConnection.new
        connection.data_sources = ["schema_migrations", "users", "internal_metadata", "posts"]
        task.define_singleton_method(:connection) { connection }
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args| commands << [cmd, args] }
        original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        ActiveRecord::SchemaDumper.ignore_tables = ["schema_migrations", /internal/]

        task.structure_dump("/tmp/structure.sql", ["--single-transaction"])

        assert_equal "mysqldump", commands.first.first
        args = commands.first.last
        assert_equal "--single-transaction", args.first
        assert_includes args, "--host=localhost"
        assert_includes args, "--user=root"
        assert_includes args, "--result-file"
        assert_includes args, "/tmp/structure.sql"
        assert_includes args, "--no-data"
        assert_includes args, "--routines"
        assert_includes args, "--skip-comments"
        assert_includes args, "--ignore-table=app_db.schema_migrations"
        assert_includes args, "--ignore-table=app_db.internal_metadata"
        assert_equal "app_db", args.last
      ensure
        ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
      end

      def test_structure_dump_without_ignored_tables_or_extra_flags
        task = build_task
        task.define_singleton_method(:connection) { FakeConnection.new }
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args| commands << [cmd, args] }
        original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
        ActiveRecord::SchemaDumper.ignore_tables = []

        task.structure_dump("schema.sql", nil)

        args = commands.first.last
        assert_equal "mysqldump", commands.first.first
        assert_not_includes args.join(" "), "--ignore-table"
        assert_equal "app_db", args.last
      ensure
        ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
      end

      def test_structure_load_builds_mysql_command_with_or_without_extra_flags
        task = build_task(socket: "/tmp/mysql.sock")
        commands = []
        task.define_singleton_method(:run_cmd) { |cmd, *args| commands << [cmd, args] }

        task.structure_load("/tmp/structure.sql", ["--force"])
        task.structure_load("/tmp/structure.sql", nil)

        assert_equal "mysql", commands[0].first
        assert_equal "--force", commands[0].last.first
        assert_includes commands[0].last, "--socket=/tmp/mysql.sock"
        assert_includes commands[0].last, "--database"
        assert_includes commands[0].last, "app_db"
        assert_includes commands[0].last, "--execute"
        assert_includes commands[0].last, "SET FOREIGN_KEY_CHECKS = 0; SOURCE /tmp/structure.sql; SET FOREIGN_KEY_CHECKS = 1"

        assert_equal "mysql", commands[1].first
        assert_equal "--socket=/tmp/mysql.sock", commands[1].last.first
      end
    end
  end
end
