# frozen_string_literal: true

require "abstract_unit"
require "rails/generators/rails/plugin/plugin_generator"

class PluginBuilderPublicContractTest < ActiveSupport::TestCase
  class RecordingGenerator
    attr_reader :calls, :options

    def initialize(options = {}, responses = {})
      @options = options
      @responses = responses
      @calls = []
    end

    def method_missing(name, *args, **kwargs, &block)
      calls << [name, args, kwargs]
      block.call("script body") if block
      @responses[name]
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end

  def builder(options = {}, responses = {})
    Rails::PluginBuilder.include(Rails::ActionMethods)
    generator = RecordingGenerator.new(options, responses)
    [Rails::PluginBuilder.new(generator), generator]
  end

  test "bin installs plugin binstubs with engine and rubocop exclusions" do
    plugin_builder, generator = builder({}, engine?: false, skip_rubocop?: false, shebang: "#!/usr/bin/env ruby")
    plugin_builder.bin

    directory_call = generator.calls.find { |name,| name == :directory }
    assert_equal "bin", directory_call[1][0]
    exclude_pattern = directory_call[1][1][:exclude_pattern].inspect
    assert_includes exclude_pattern, "rails"
    assert_not_includes exclude_pattern, "test"
    assert_no_match(/rubocop/, exclude_pattern)
    assert_equal [:chmod, ["bin", 0755 & ~File.umask], { verbose: false }], generator.calls.last

    engine_builder, engine_generator = builder({}, engine?: true, skip_rubocop?: false, shebang: "#!/usr/bin/env ruby")
    engine_builder.bin

    engine_directory_call = engine_generator.calls.find { |name,| name == :directory }
    engine_exclude_pattern = engine_directory_call[1][1][:exclude_pattern].inspect
    assert_includes engine_exclude_pattern, "test"
    assert_not_includes engine_exclude_pattern, "rails"

    skip_rubocop_builder, skip_rubocop_generator = builder({}, engine?: false, skip_rubocop?: true, shebang: "#!/usr/bin/env ruby")
    skip_rubocop_builder.bin

    skip_rubocop_directory_call = skip_rubocop_generator.calls.find { |name,| name == :directory }
    assert_match(/rubocop/, skip_rubocop_directory_call[1][1][:exclude_pattern].inspect)
  end

  test "cifiles creates GitHub workflow templates" do
    plugin_builder, generator = builder

    plugin_builder.cifiles

    assert_equal [
      [:empty_directory, [".github/workflows"], {}],
      [:template, ["github/ci.yml", ".github/workflows/ci.yml"], {}],
      [:template, ["github/dependabot.yml", ".github/dependabot.yml"], {}]
    ], generator.calls
  end

  test "config creates routes only for engines" do
    engine_builder, engine_generator = builder({}, engine?: true)
    engine_builder.config

    assert_equal [[:engine?, [], {}], [:template, ["config/routes.rb"], {}]], engine_generator.calls

    plugin_builder, plugin_generator = builder({}, engine?: false)
    plugin_builder.config

    assert_equal [[:engine?, [], {}]], plugin_generator.calls
  end

  test "root file helpers delegate to plugin templates" do
    plugin_builder, generator = builder

    plugin_builder.rakefile
    plugin_builder.readme
    plugin_builder.gemfile
    plugin_builder.gemspec
    plugin_builder.gitignore
    plugin_builder.rubocop

    assert_equal [
      [:template, ["Rakefile"], {}],
      [:template, ["README.md"], {}],
      [:template, ["Gemfile"], {}],
      [:template, ["%name%.gemspec"], {}],
      [:template, ["gitignore", ".gitignore"], {}],
      [:template, ["rubocop.yml", ".rubocop.yml"], {}]
    ], generator.calls
  end

  test "license is skipped when generated inside an application" do
    plugin_builder, generator = builder({}, inside_application?: false)
    plugin_builder.license

    assert_equal [[:inside_application?, [], {}], [:template, ["MIT-LICENSE"], {}]], generator.calls

    inside_app_builder, inside_app_generator = builder({}, inside_application?: true)
    inside_app_builder.license

    assert_equal [[:inside_application?, [], {}]], inside_app_generator.calls
  end
end
