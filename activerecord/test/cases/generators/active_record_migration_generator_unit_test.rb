# frozen_string_literal: true

require "cases/helper"
require "rails/generators"
require "rails/generators/active_record/migration/migration_generator"
require "ostruct"

class ActiveRecordMigrationGeneratorUnitTest < ActiveRecord::TestCase
  Attribute = Struct.new(:name, :plural_name, :singular_name, :foreign_key_value, :reference_value, :has_index_value, :index_name, keyword_init: true) do
    def foreign_key? = foreign_key_value
    def reference? = reference_value
    def has_index? = has_index_value
  end

  def test_next_migration_number_uses_current_number_plus_one
    generator_class = Class.new do
      include ActiveRecord::Generators::Migration
      def self.current_migration_number(dirname)
        dirname == "db/migrate" ? 41 : 0
      end
    end

    assert_equal ActiveRecord::Migration.next_migration_number(42), generator_class.next_migration_number("db/migrate")
  end

  def test_primary_and_foreign_key_type_follow_primary_key_type_option
    generator = migration_module_instance(primary_key_type: "uuid")

    assert_equal ", id: :uuid", generator.send(:primary_key_type)
    assert_equal ", type: :uuid", generator.send(:foreign_key_type)

    generator = migration_module_instance
    assert_nil generator.send(:primary_key_type)
    assert_nil generator.send(:foreign_key_type)
  end

  def test_db_migrate_path_uses_default_when_no_application_is_available
    generator = migration_module_instance
    Rails.define_singleton_method(:application) { nil } unless Rails.respond_to?(:application)

    Rails.stub(:application, nil) do
      assert_equal "db/migrate", generator.send(:db_migrate_path)
    end
  end

  def test_db_migrate_path_prefers_configured_database_migration_path_then_default
    generator = migration_module_instance(database: "animals")
    app = Object.new
    paths = { "db/migrate" => Object.new }
    paths["db/migrate"].define_singleton_method(:to_ary) { ["db/migrate"] }
    app.define_singleton_method(:config) { OpenStruct.new(paths: paths) }
    db_config = OpenStruct.new(migrations_paths: ["db/animals_migrate"])

    Rails.define_singleton_method(:application) { app } unless Rails.respond_to?(:application)
    Rails.define_singleton_method(:env) { "test" } unless Rails.respond_to?(:env)

    Rails.stub(:application, app) do
      Rails.stub(:env, "test") do
        ActiveRecord::Base.configurations.stub(:configs_for, db_config) do
          assert_equal "db/animals_migrate", generator.send(:db_migrate_path)
        end
      end
    end

    generator = migration_module_instance
    Rails.stub(:application, app) do
      assert_equal "db/migrate", generator.send(:db_migrate_path)
    end
  end

  def test_set_local_assigns_detects_add_remove_create_and_join_migrations
    generator = migration_generator(file_name: "add_name_to_users")
    generator.send(:set_local_assigns!)
    assert_equal "migration.rb", generator.instance_variable_get(:@migration_template)
    assert_equal "add", generator.send(:migration_action)
    assert_equal "users", generator.instance_variable_get(:@table_name)

    generator = migration_generator(file_name: "remove_name_from_people", pluralize: false)
    generator.send(:set_local_assigns!)
    assert_equal "remove", generator.send(:migration_action)
    assert_equal "person", generator.instance_variable_get(:@table_name)

    generator = migration_generator(file_name: "create_person")
    generator.send(:set_local_assigns!)
    assert_equal "create_table_migration.rb", generator.instance_variable_get(:@migration_template)
    assert_equal "people", generator.instance_variable_get(:@table_name)

    first = Attribute.new(name: "user", plural_name: "users", singular_name: "user", foreign_key_value: false)
    second = Attribute.new(name: "role_id", plural_name: "roles", singular_name: "role", foreign_key_value: true)
    generator = migration_generator(file_name: "create_join_table", attributes: [first, second])
    generator.send(:set_local_assigns!)
    assert_equal "join", generator.send(:migration_action)
    assert_equal ["users", "roles"], generator.send(:join_tables)
    assert_equal [:user_id, :role_id], first.index_name
    assert_equal [:role_id, :user_id], second.index_name

    generator = migration_generator(file_name: "create_join_table", attributes: [first, second], pluralize: false)
    generator.send(:set_local_assigns!)
    assert_equal ["user", "role"], generator.send(:join_tables)
  end

  def test_join_table_requires_two_attributes
    generator = migration_generator(file_name: "create_join_table", attributes: [Attribute.new(name: "user")])

    generator.send(:set_local_assigns!)

    assert_nil generator.send(:migration_action)
    assert_nil generator.send(:join_tables)
  end

  def test_set_local_assigns_leaves_unknown_migration_names_on_default_template
    generator = migration_generator(file_name: "change_users")

    generator.send(:set_local_assigns!)

    assert_equal "migration.rb", generator.instance_variable_get(:@migration_template)
    assert_nil generator.send(:migration_action)
  end

  def test_configured_migrate_path_returns_nil_when_database_config_is_missing
    generator = migration_module_instance(database: "missing")
    app = Object.new
    paths = { "db/migrate" => Object.new }
    paths["db/migrate"].define_singleton_method(:to_ary) { ["db/migrate"] }
    app.define_singleton_method(:config) { OpenStruct.new(paths: paths) }

    Rails.define_singleton_method(:application) { app } unless Rails.respond_to?(:application)
    Rails.define_singleton_method(:env) { "test" } unless Rails.respond_to?(:env)

    Rails.stub(:application, app) do
      Rails.stub(:env, "test") do
        ActiveRecord::Base.configurations.stub(:configs_for, nil) do
          assert_equal "db/migrate", generator.send(:db_migrate_path)
        end
      end
    end
  end

  def test_index_name_for_and_attributes_with_index
    regular = Attribute.new(name: "people", foreign_key_value: false, reference_value: false, has_index_value: true)
    reference = Attribute.new(name: "account", foreign_key_value: true, reference_value: true, has_index_value: true)
    plain = Attribute.new(name: "title", foreign_key_value: false, reference_value: false, has_index_value: false)
    generator = migration_generator(attributes: [regular, reference, plain])

    assert_equal :person_id, generator.send(:index_name_for, regular)
    assert_equal :account, generator.send(:index_name_for, reference)
    assert_equal [regular], generator.send(:attributes_with_index)
  end

  def test_validate_file_name_rejects_invalid_migration_names
    generator = migration_generator(file_name: "valid_123")
    assert_nil generator.send(:validate_file_name!)

    generator = migration_generator(file_name: "Invalid-Name")
    assert_raises(ActiveRecord::IllegalMigrationNameError) { generator.send(:validate_file_name!) }
  end

  def test_create_migration_file_sets_locals_validates_name_and_uses_migration_template
    generator = migration_generator(file_name: "create_users")
    calls = []
    generator.define_singleton_method(:migration_template) { |template, destination| calls << [template, destination] }
    generator.define_singleton_method(:db_migrate_path) { "db/custom_migrate" }

    generator.create_migration_file

    assert_equal [["create_table_migration.rb", "db/custom_migrate/create_users.rb"]], calls
  end

  private
    def migration_module_instance(options = {})
      Class.new do
        include ActiveRecord::Generators::Migration
        define_method(:options) { options }
      end.new
    end

    def migration_generator(file_name: "create_users", attributes: [], pluralize: true)
      ActiveRecord::Generators::MigrationGenerator.allocate.tap do |generator|
        generator.define_singleton_method(:file_name) { file_name }
        generator.define_singleton_method(:attributes) { attributes }
        generator.define_singleton_method(:pluralize_table_names?) { pluralize }
        generator.define_singleton_method(:options) { {} }
      end
    end
end
