# frozen_string_literal: true

require "cases/helper"
require "rails/generators"
require "rails/generators/actions"
require "rails/generators/active_record"
require "rails/generators/active_record/application_record/application_record_generator"
Rails::Generators.stub(:templates_path, ["/tmp/templates"]) do
  require "rails/generators/active_record/model/model_generator"
end
require "rails/generators/active_record/multi_db/multi_db_generator"

class ActiveRecordGeneratorsUnitTest < ActiveRecord::TestCase
  Attribute = Struct.new(:reference_value, :has_index_value, :attr_options, keyword_init: true) do
    def reference? = reference_value
    def has_index? = has_index_value
  end

  test "base root points at active record generator directory" do
    assert_equal File.expand_path("../../../lib/rails/generators", __dir__), ActiveRecord::Generators::Base.base_root
  end

  test "application record generator creates default application record" do
    generator = application_record_generator(namespaced: false)

    generator.create_application_record

    assert_equal [["application_record.rb", "app/models/application_record.rb"]], generator.template_calls
  end

  test "application record generator creates namespaced application record" do
    generator = application_record_generator(namespaced: true, namespaced_path: "admin")

    generator.create_application_record

    assert_equal [["application_record.rb", "app/models/admin/application_record.rb"]], generator.template_calls
  end

  test "model generator adds configured template migration paths when loaded" do
    assert_includes ActiveRecord::Generators::ModelGenerator.source_paths, "/tmp/templates/active_record/migration"
  end

  test "model generator skips migration for custom parent without database" do
    generator = model_generator(options: { parent: "Admin::Record", migration: true })

    generator.create_migration_file

    assert_empty generator.migration_template_calls
  end

  test "model generator creates migration and removes implicit reference indexes when disabled" do
    reference = Attribute.new(reference_value: true, has_index_value: false, attr_options: { index: true })
    explicit_reference = Attribute.new(reference_value: true, has_index_value: true, attr_options: { index: true })
    generator = model_generator(
      attributes: [reference, explicit_reference],
      options: { parent: "ApplicationRecord", migration: true, indexes: false }
    )

    generator.create_migration_file

    assert_equal [["create_table_migration.rb", "db/migrate/create_accounts.rb"]], generator.migration_template_calls
    assert_empty reference.attr_options
    assert_equal({ index: true }, explicit_reference.attr_options)
  end

  test "model generator creates model with default parent" do
    generator = model_generator(options: { parent: "ApplicationRecord" })

    generator.create_model_file

    assert_equal [["model.rb", "app/models/account.rb"]], generator.template_calls
  end

  test "model generator creates database abstract class when database option is used" do
    generator = model_generator(options: { parent: "ApplicationRecord", database: "animals" })

    generator.create_model_file

    assert_equal [["abstract_base_class.rb", "app/models/animals_record.rb"], ["model.rb", "app/models/account.rb"]], generator.template_calls
  end

  test "model generator does not overwrite existing database abstract class" do
    path = File.join("app/models", "animals_record.rb")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "existing")
    generator = model_generator(options: { parent: "ApplicationRecord", database: "animals" })

    generator.create_model_file

    assert_equal [["model.rb", "app/models/account.rb"]], generator.template_calls
  ensure
    FileUtils.rm_f(path) if path
  end

  test "model generator uses custom parent instead of generated database abstract class" do
    generator = model_generator(options: { parent: "Admin::Record", database: "animals" })

    generator.create_model_file

    assert_equal [["model.rb", "app/models/account.rb"]], generator.template_calls
    assert_equal "Admin::Record", generator.send(:parent_class_name)
  end

  test "model generator creates module file only for nested invoked class" do
    generator = model_generator(class_path: %w[admin account], regular_class_path: %w[admin], behavior: :invoke)

    generator.create_module_file

    assert_equal [["module.rb", "app/models/admin/account.rb"]], generator.template_calls
  end

  test "model generator skips module file for root class and revoke behavior" do
    root_generator = model_generator(regular_class_path: [])
    root_generator.create_module_file
    assert_empty root_generator.template_calls

    revoke_generator = model_generator(class_path: %w[admin], regular_class_path: %w[admin], behavior: :revoke)
    revoke_generator.create_module_file
    assert_empty revoke_generator.template_calls
  end

  test "model generator exposes database parent and migration helpers" do
    indexed = Attribute.new(reference_value: false, has_index_value: true, attr_options: {})
    generator = model_generator(attributes: [indexed], options: { parent: "ApplicationRecord", database: "animals", migration: false })

    assert_equal "AnimalsRecord", generator.send(:parent_class_name)
    assert_equal [indexed], generator.send(:attributes_with_index)
    assert generator.send(:skip_migration_creation?)
  end

  test "model generator parent class helper handles custom and default parents" do
    custom = model_generator(options: { parent: "Admin::Record" })
    default = model_generator(options: { parent: "ApplicationRecord" })

    assert_equal "Admin::Record", custom.send(:parent_class_name)
    assert_equal "ApplicationRecord", default.send(:parent_class_name)
  end

  test "model generator create migration returns early when migration is disabled" do
    generator = model_generator(options: { parent: "ApplicationRecord", migration: false })

    generator.create_migration_file

    assert_empty generator.migration_template_calls
  end

  test "model generator create migration keeps reference indexes by default" do
    reference = Attribute.new(reference_value: true, has_index_value: false, attr_options: { index: true })
    generator = model_generator(attributes: [reference], options: { parent: "ApplicationRecord", migration: true, indexes: true })

    generator.create_migration_file

    assert_equal({ index: true }, reference.attr_options)
    assert_equal [["create_table_migration.rb", "db/migrate/create_accounts.rb"]], generator.migration_template_calls
  end

  test "model generator generate abstract class returns when file exists" do
    generator = model_generator(options: { parent: "ApplicationRecord", database: "animals" })

    File.stub(:exist?, true) do
      generator.send(:generate_abstract_class)
    end

    assert_empty generator.template_calls
  end

  test "multi db generator creates initializer" do
    generator = multi_db_generator

    generator.create_multi_db

    assert_equal [["multi_db.rb", "config/initializers/multi_db.rb"]], generator.template_calls
  end

  private
    def application_record_generator(namespaced:, namespaced_path: nil)
      ActiveRecord::Generators::ApplicationRecordGenerator.allocate.tap do |generator|
        attach_template_recorder(generator)
        generator.define_singleton_method(:namespaced?) { namespaced }
        generator.define_singleton_method(:namespaced_path) { namespaced_path }
      end
    end

    def model_generator(attributes: [], options: {}, class_path: [], regular_class_path: [], behavior: :invoke)
      defaults = { parent: "ApplicationRecord", migration: true, indexes: true }
      opts = defaults.merge(options)
      ActiveRecord::Generators::ModelGenerator.allocate.tap do |generator|
        attach_template_recorder(generator)
        calls = []
        generator.define_singleton_method(:migration_template_calls) { calls }
        generator.define_singleton_method(:migration_template) { |template, destination| calls << [template, destination] }
        generator.define_singleton_method(:attributes) { attributes }
        generator.define_singleton_method(:options) { opts }
        generator.define_singleton_method(:table_name) { "accounts" }
        generator.define_singleton_method(:db_migrate_path) { "db/migrate" }
        generator.define_singleton_method(:file_name) { "account" }
        generator.define_singleton_method(:class_path) { class_path }
        generator.define_singleton_method(:regular_class_path) { regular_class_path }
        generator.define_singleton_method(:behavior) { behavior }
      end
    end

    def multi_db_generator
      ActiveRecord::Generators::MultiDbGenerator.allocate.tap do |generator|
        attach_template_recorder(generator)
      end
    end

    def attach_template_recorder(generator)
      calls = []
      generator.define_singleton_method(:template_calls) { calls }
      generator.define_singleton_method(:template) { |template, destination| calls << [template, destination] }
    end
end
