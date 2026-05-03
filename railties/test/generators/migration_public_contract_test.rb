# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/migration"

class MigrationPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  class Migrator < Rails::Generators::Base
    include Rails::Generators::Migration

    source_root File.expand_path("fixtures/migration_templates", __dir__)

    def self.next_migration_number(dirname)
      current_migration_number(dirname) + 1
    end
  end

  tests Migrator
  setup :prepare_destination

  def setup
    super
    @generated_files = Rails::Generators.class_variable_get(:@@generated_files) if Rails::Generators.class_variable_defined?(:@@generated_files)
    Rails::Generators.class_variable_set(:@@generated_files, [])
  end

  def teardown
    if defined?(@generated_files)
      Rails::Generators.class_variable_set(:@@generated_files, @generated_files)
    elsif Rails::Generators.class_variable_defined?(:@@generated_files)
      Rails::Generators.remove_class_variable(:@@generated_files)
    end
    super
  end

  test "next migration number must be implemented by including generators" do
    assert_raises(NotImplementedError) do
      Rails::Generators::Migration::ClassMethods.instance_method(:next_migration_number).bind_call(Migrator.singleton_class, destination_root)
    end
  end

  test "set migration assigns derives number, file name, and class name" do
    generator.set_migration_assigns!("db/migrate/create_posts.rb")

    assert_equal 1, generator.migration_number
    assert_equal "create_posts", generator.migration_file_name
    assert_equal "CreatePosts", generator.migration_class_name
  end

  test "create migration delegates to the migration action" do
    generator.set_migration_assigns!("db/migrate/create_posts.rb")

    capture(:stdout) do
      generator.create_migration("db/migrate/%migration_number%_create_posts.rb", "class CreatePosts < ActiveRecord::Migration[8.2]\nend\n")
    end

    assert_file "db/migrate/1_create_posts.rb", /class CreatePosts/
  end

  test "migration template renders assigns and records generated file" do
    FileUtils.mkdir_p(File.join(Migrator.source_root))
    File.write(File.join(Migrator.source_root, "migration.rb.tt"), <<~'ERB')
      class <%= migration_class_name %> < ActiveRecord::Migration[8.2]
        def change
          create_table :<%= migration_file_name.delete_prefix("create_") %>
        end
      end
    ERB

    capture(:stdout) do
      generator.migration_template("migration.rb.tt", "db/migrate/create_posts.rb")
    end

    assert_file "db/migrate/1_create_posts.rb", /class CreatePosts/
    assert_file "db/migrate/1_create_posts.rb", /create_table :posts/
    assert_equal ["db/migrate/1_create_posts.rb"], Rails::Generators.class_variable_get(:@@generated_files)
  ensure
    FileUtils.rm_f(File.join(Migrator.source_root, "migration.rb.tt"))
  end
end
