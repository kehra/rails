# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/generated_attribute"

class TestingAssertionsPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  setup :prepare_destination

  test "file assertions check existence content and yielded content" do
    FileUtils.mkdir_p(File.join(destination_root, "app/models"))
    File.write(File.join(destination_root, "app/models/post.rb"), "class Post\n  def title\n    \"hello\"\n  end\n\n  def self.visible\n    true\n  end\nend\n")

    assert_file "app/models/post.rb", File.read(File.join(destination_root, "app/models/post.rb")), /class Post/, :ignored_content_matcher do |content|
      assert_instance_method :title, content do |method_body|
        assert_equal '"hello"', method_body
      end

      assert_class_method :visible, content do |method_body|
        assert_equal "true", method_body
      end

      assert_instance_method :title, content
    end
    assert_directory "app/models"
    assert_no_file "app/models/comment.rb"
    assert_no_directory "app/controllers"
  end

  test "migration assertions find timestamped migration files" do
    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    File.write(File.join(destination_root, "db/migrate/20240503000000_create_posts.rb"), "class CreatePosts\nend\n")

    assert_migration "db/migrate/create_posts.rb", /CreatePosts/
    assert_no_migration "db/migrate/create_comments.rb"
  end

  test "field default and type assertions delegate to generated attributes" do
    assert_field_type :date, :date_field
    assert_field_default_value :string, "MyString"
    assert_field_default_value :references, nil
  end

  test "initializer assertion checks files under config initializers" do
    FileUtils.mkdir_p(File.join(destination_root, "config/initializers"))
    File.write(File.join(destination_root, "config/initializers/demo.rb"), "Demo = true\n")

    assert_initializer "demo.rb", /Demo = true/
  end
end
