# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/resource_helpers"

class ResourceHelpersPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  class MissingOrmOptionGenerator < Rails::Generators::NamedBase
    include Rails::Generators::ResourceHelpers

    public :orm_class
  end

  class NamedControllerGenerator < Rails::Generators::NamedBase
    include Rails::Generators::ResourceHelpers
    class_option :orm, type: :string, default: "active_record"

    public :controller_class_path, :controller_file_name, :controller_file_path, :controller_class_name, :controller_i18n_scope, :orm_class, :orm_instance
  end

  test "resource helpers require an orm class option before resolving the orm class" do
    generator = MissingOrmOptionGenerator.new(["post"])

    error = assert_raises(RuntimeError) { generator.orm_class }
    assert_equal "You need to have :orm as class option to invoke orm_class and orm_instance", error.message
  end

  test "resource helpers split explicit model and controller names independently" do
    generator = NamedControllerGenerator.new(["admin/posts"], model_name: "Article", orm: "unknown")

    assert_equal ["admin"], generator.controller_class_path
    assert_equal "posts", generator.controller_file_name
    assert_equal "admin/posts", generator.controller_file_path
    assert_equal "Admin::Posts", generator.controller_class_name
    assert_equal "admin.posts", generator.controller_i18n_scope
    assert_equal Rails::Generators::ActiveModel, generator.orm_class
    assert_instance_of Rails::Generators::ActiveModel, generator.orm_instance

    default_generator = NamedControllerGenerator.new(["admin/post"], orm: "active_record")
    assert_equal ["admin"], default_generator.controller_class_path
  end
end
