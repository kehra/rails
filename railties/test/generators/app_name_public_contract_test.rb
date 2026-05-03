# frozen_string_literal: true

require "abstract_unit"
require "rails/generators"
require "rails/generators/base"
require "rails/generators/app_name"

class AppNamePublicContractTest < ActiveSupport::TestCase
  class Generator
    include Rails::Generators::AppName

    attr_reader :destination_root, :options

    def initialize(destination_root, options = {})
      @destination_root = destination_root
      @options = options
    end
  end

  test "derives normalized names and constants from destination root" do
    generator = Generator.new("/tmp/my-blog.app")

    assert_equal "my_blog_app", generator.send(:app_name)
    assert_equal "my-blog.app", generator.send(:original_app_name)
    assert_equal "MyBlogApp", generator.send(:app_const_base)
    assert_equal "MyBlogApp", generator.send(:camelized)
    assert_equal "MyBlogApp::Application", generator.send(:app_const)
    assert_nil generator.send(:valid_const?)
  end

  test "name option overrides destination basename" do
    generator = Generator.new("/tmp/ignored", name: "Admin-Portal")

    assert_equal "Admin-Portal", generator.send(:original_app_name)
    assert_equal "admin_portal", generator.send(:app_name)
    assert_equal "AdminPortal::Application", generator.send(:app_const)
  end

  test "valid const rejects names starting with numbers" do
    error = assert_raises(Rails::Generators::Error) do
      Generator.new("/tmp/123-demo").send(:valid_const?)
    end

    assert_match(/does not start with numbers/, error.message)
  end

  test "valid const rejects reserved rails words" do
    error = assert_raises(Rails::Generators::Error) do
      Generator.new("/tmp/plugin").send(:valid_const?)
    end

    assert_match(/reserved rails words/, error.message)
  end

  test "valid const rejects existing top level constants" do
    Object.const_set(:TakenAppName, Class.new)

    error = assert_raises(Rails::Generators::Error) do
      Generator.new("/tmp/taken_app_name").send(:valid_const?)
    end

    assert_match(/constant TakenAppName is already in use/, error.message)
  ensure
    Object.send(:remove_const, :TakenAppName) if Object.const_defined?(:TakenAppName)
  end
end
