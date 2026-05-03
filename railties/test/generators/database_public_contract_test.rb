# frozen_string_literal: true

require "abstract_unit"
require "minitest/mock"
require "rails/generators/database"

class DatabasePublicContractTest < ActiveSupport::TestCase
  test "build maps supported names and falls back to null database" do
    assert_instance_of Rails::Generators::Database::MySQL2, Rails::Generators::Database.build("mysql")
    assert_instance_of Rails::Generators::Database::PostgreSQL, Rails::Generators::Database.build("postgresql")
    assert_instance_of Rails::Generators::Database::Trilogy, Rails::Generators::Database.build("trilogy")
    assert_instance_of Rails::Generators::Database::SQLite3, Rails::Generators::Database.build("sqlite3")
    assert_instance_of Rails::Generators::Database::MariaDBMySQL2, Rails::Generators::Database.build("mariadb-mysql")
    assert_instance_of Rails::Generators::Database::MariaDBTrilogy, Rails::Generators::Database.build("mariadb-trilogy")
    assert_instance_of Rails::Generators::Database::Null, Rails::Generators::Database.build("unknown")
  end

  test "all returns the databases offered by the application generator" do
    assert_equal [
      Rails::Generators::Database::MySQL2,
      Rails::Generators::Database::PostgreSQL,
      Rails::Generators::Database::SQLite3,
      Rails::Generators::Database::MariaDBMySQL2,
      Rails::Generators::Database::MariaDBTrilogy,
    ], Rails::Generators::Database.all.map(&:class)
  end

  test "abstract database raises for adapter specific methods and derives feature and volume" do
    database = Rails::Generators::Database.new

    assert_raises(NotImplementedError) { database.name }
    assert_raises(NotImplementedError) { database.template }
    assert_raises(NotImplementedError) { database.service }
    assert_raises(NotImplementedError) { database.port }
    assert_raises(NotImplementedError) { database.feature_name }
    assert_raises(NotImplementedError) { database.gem }
    assert_raises(NotImplementedError) { database.base_package }
    assert_raises(NotImplementedError) { database.build_package }
    assert_nil database.socket
    assert_nil database.host
  end

  test "feature and volume use adapter feature_name, service, and name" do
    database = Class.new(Rails::Generators::Database) do
      def feature_name = "feature/id"
      def service = { "image" => "database" }
      def name = "database"
    end.new

    assert_equal({ "feature/id" => {} }, database.feature)
    assert_equal "database-data", database.volume
  end

  test "feature and volume are omitted when adapter has no feature or service" do
    database = Class.new(Rails::Generators::Database) do
      def feature_name = nil
      def service = nil
    end.new

    assert_nil database.feature
    assert_nil database.volume
  end

  test "mysql family adapters expose client metadata and service configuration" do
    mysql2 = Rails::Generators::Database::MySQL2.new
    trilogy = Rails::Generators::Database::Trilogy.new
    mariadb_mysql2 = Rails::Generators::Database::MariaDBMySQL2.new
    mariadb_trilogy = Rails::Generators::Database::MariaDBTrilogy.new

    assert_equal "mysql", mysql2.name
    assert_equal 3306, mysql2.port
    assert_equal "127.0.0.1", mysql2.host
    assert_equal "config/databases/mysql.yml", mysql2.template
    assert_equal ["mysql2", ["~> 0.5"]], mysql2.gem
    assert_equal "default-mysql-client", mysql2.base_package
    assert_equal "default-libmysqlclient-dev", mysql2.build_package
    assert_equal "ghcr.io/rails/devcontainer/features/mysql-client", mysql2.feature_name
    assert_equal "mysql-data", mysql2.volume
    assert_equal "mysql/mysql-server:8.0", mysql2.service["image"]

    assert_equal "config/databases/trilogy.yml", trilogy.template
    assert_equal ["trilogy", ["~> 2.7"]], trilogy.gem
    assert_equal "default-mysql-client", trilogy.base_package
    assert_nil trilogy.build_package
    assert_nil trilogy.feature_name
    assert_nil trilogy.feature

    assert_equal "mariadb", mariadb_mysql2.name
    assert_equal 3306, mariadb_mysql2.port
    assert_equal "mariadb:10.5", mariadb_mysql2.service["image"]
    assert_equal "mariadb-data", mariadb_mysql2.volume
    assert_equal "config/databases/mysql.yml", mariadb_mysql2.template
    assert_equal ["mysql2", ["~> 0.5"]], mariadb_mysql2.gem

    assert_equal "mariadb", mariadb_trilogy.name
    assert_equal "mariadb:10.5", mariadb_trilogy.service["image"]
    assert_equal "config/databases/trilogy.yml", mariadb_trilogy.template
    assert_equal ["trilogy", ["~> 2.7"]], mariadb_trilogy.gem
  end

  test "mysql socket returns the first known socket path that exists" do
    database = Rails::Generators::Database::MySQL2.new

    Gem.stub(:win_platform?, false) do
      File.stub(:exist?, ->(path) { path == "/var/run/mysqld/mysqld.sock" }) do
        assert_equal "/var/run/mysqld/mysqld.sock", database.socket
      end
    end
  end

  test "mysql socket is omitted on windows platforms" do
    database = Rails::Generators::Database::MySQL2.new

    Gem.stub(:win_platform?, true) do
      assert_nil database.socket
    end
  end

  test "postgresql adapter exposes client metadata and service configuration" do
    database = Rails::Generators::Database::PostgreSQL.new

    assert_equal "postgres", database.name
    assert_equal "config/databases/postgresql.yml", database.template
    assert_equal "postgres:18", database.service["image"]
    assert_equal 5432, database.port
    assert_equal ["pg", ["~> 1.1"]], database.gem
    assert_equal "postgresql-client", database.base_package
    assert_equal "libpq-dev", database.build_package
    assert_equal "ghcr.io/rails/devcontainer/features/postgres-client", database.feature_name
    assert_equal({ "ghcr.io/rails/devcontainer/features/postgres-client" => {} }, database.feature)
    assert_equal "postgres-data", database.volume
  end

  test "sqlite3 adapter exposes generator metadata without external services" do
    database = Rails::Generators::Database::SQLite3.new

    assert_equal "sqlite3", database.name
    assert_equal "config/databases/sqlite3.yml", database.template
    assert_nil database.service
    assert_nil database.port
    assert_equal ["sqlite3", [">= 2.1"]], database.gem
    assert_equal "sqlite3", database.base_package
    assert_nil database.build_package
    assert_equal "ghcr.io/rails/devcontainer/features/sqlite3", database.feature_name
    assert_equal({ "ghcr.io/rails/devcontainer/features/sqlite3" => {} }, database.feature)
    assert_nil database.volume
  end

  test "null adapter omits every optional database integration" do
    database = Rails::Generators::Database::Null.new

    assert_nil database.name
    assert_nil database.template
    assert_nil database.service
    assert_nil database.port
    assert_nil database.volume
    assert_nil database.base_package
    assert_nil database.build_package
    assert_nil database.feature_name
    assert_nil database.feature
  end
end
