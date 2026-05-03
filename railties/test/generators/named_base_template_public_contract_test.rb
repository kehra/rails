# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/named_base"

class NamedBaseTemplatePublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  class TemplateGenerator < Rails::Generators::NamedBase
    source_root File.expand_path("fixtures/named_base_templates", __dir__)

    def copy_templates
      template "plain.txt.tt", "plain.txt"
      js_template "script", "script"
    end
  end

  tests TemplateGenerator
  setup :prepare_destination

  def setup
    super
    @generated_files = Rails::Generators.class_variable_get(:@@generated_files) if Rails::Generators.class_variable_defined?(:@@generated_files)
    Rails::Generators.class_variable_set(:@@generated_files, [])
    FileUtils.mkdir_p(TemplateGenerator.source_root)
    File.write(File.join(TemplateGenerator.source_root, "plain.txt.tt"), "<%= class_name %> / <%= file_path %>\n")
    File.write(File.join(TemplateGenerator.source_root, "script.js"), "console.log('<%= class_name %>');\n")
  end

  def teardown
    FileUtils.rm_rf(TemplateGenerator.source_root)
    if defined?(@generated_files)
      Rails::Generators.class_variable_set(:@@generated_files, @generated_files)
    elsif Rails::Generators.class_variable_defined?(:@@generated_files)
      Rails::Generators.remove_class_variable(:@@generated_files)
    end
    super
  end

  test "template records the generated file while rendering inside template context" do
    run_generator ["Admin::Post"]

    assert_file "plain.txt", "Admin::Post / admin/post\n"
    assert_file "script.js", "console.log('Admin::Post');\n"
    assert_equal ["plain.txt", "script.js"], Rails::Generators.class_variable_get(:@@generated_files)
  end
end
