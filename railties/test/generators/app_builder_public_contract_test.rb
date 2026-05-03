# frozen_string_literal: true

require "abstract_unit"
require "rails/generators/rails/app/app_generator"

class AppBuilderPublicContractTest < ActiveSupport::TestCase
  class RecordingGenerator
    attr_reader :calls, :options

    def initialize(options = {})
      @options = options
      @calls = []
    end

    def method_missing(name, *args, **kwargs, &block)
      calls << [name, args, kwargs]
      block.call("content") if block
      nil
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end

  def builder(options = {})
    Rails::AppBuilder.include(Rails::ActionMethods)
    Rails::AppBuilder.new(RecordingGenerator.new(options))
  end

  test "root file helpers delegate to the expected template and copy actions" do
    builder = builder()

    builder.rakefile
    builder.readme
    builder.ruby_version
    builder.node_version
    builder.gemfile
    builder.configru
    builder.gitignore
    builder.gitattributes
    builder.rubocop

    assert_equal [
      [:template, ["Rakefile"], {}],
      [:copy_file, ["README.md", "README.md"], {}],
      [:template, ["ruby-version", ".ruby-version"], {}],
      [:template, ["node-version", ".node-version"], {}],
      [:template, ["Gemfile"], {}],
      [:template, ["config.ru"], {}],
      [:template, ["gitignore", ".gitignore"], {}],
      [:template, ["gitattributes", ".gitattributes"], {}],
      [:template, ["rubocop.yml", ".rubocop.yml"], {}]
    ], builder.instance_variable_get(:@generator).calls
  end

  test "directory helpers create the expected application skeleton paths" do
    builder = builder()

    builder.app
    builder.db
    builder.lib
    builder.log
    builder.script
    builder.storage
    builder.test
    builder.tmp
    builder.vendor

    assert_equal [
      [:directory, ["app"], {}],
      [:empty_directory_with_keep_file, ["app/assets/images"], {}],
      [:keep_file, ["app/controllers/concerns"], {}],
      [:keep_file, ["app/models/concerns"], {}],
      [:directory, ["db"], {}],
      [:empty_directory, ["lib"], {}],
      [:empty_directory_with_keep_file, ["lib/tasks"], {}],
      [:empty_directory_with_keep_file, ["log"], {}],
      [:empty_directory_with_keep_file, ["script"], {}],
      [:empty_directory_with_keep_file, ["storage"], {}],
      [:empty_directory_with_keep_file, ["tmp/storage"], {}],
      [:empty_directory_with_keep_file, ["test/fixtures/files"], {}],
      [:empty_directory_with_keep_file, ["test/controllers"], {}],
      [:empty_directory_with_keep_file, ["test/mailers"], {}],
      [:empty_directory_with_keep_file, ["test/models"], {}],
      [:empty_directory_with_keep_file, ["test/helpers"], {}],
      [:empty_directory_with_keep_file, ["test/integration"], {}],
      [:template, ["test/test_helper.rb"], {}],
      [:empty_directory_with_keep_file, ["tmp"], {}],
      [:empty_directory_with_keep_file, ["tmp/pids"], {}],
      [:empty_directory_with_keep_file, ["vendor"], {}]
    ], builder.instance_variable_get(:@generator).calls
  end

  test "config target version falls back to the current rails version" do
    assert_equal Rails::VERSION::STRING.to_f, builder.config_target_version
  end
end
