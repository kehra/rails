# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"
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

  test "lib creates railtie or engine entrypoint based on plugin type" do
    plugin_builder, generator = builder({}, engine?: false)
    plugin_builder.lib

    assert_equal [
      [:template, ["lib/%namespaced_name%.rb"], {}],
      [:template, ["lib/tasks/%namespaced_name%_tasks.rake"], {}],
      [:template, ["lib/%namespaced_name%/version.rb"], {}],
      [:engine?, [], {}],
      [:template, ["lib/%namespaced_name%/railtie.rb"], {}]
    ], generator.calls

    engine_builder, engine_generator = builder({}, engine?: true)
    engine_builder.lib

    assert_equal [
      [:template, ["lib/%namespaced_name%.rb"], {}],
      [:template, ["lib/tasks/%namespaced_name%_tasks.rake"], {}],
      [:template, ["lib/%namespaced_name%/version.rb"], {}],
      [:engine?, [], {}],
      [:template, ["lib/%namespaced_name%/engine.rb"], {}]
    ], engine_generator.calls
  end

  test "generate_test_dummy invokes app generator with plugin-specific defaults" do
    options = {
      "dev" => true,
      "edge" => true,
      "database" => "sqlite3",
      "skip_git" => false,
      "template" => "ignored.rb"
    }
    plugin_builder, generator = builder(options, dummy_path: "test/dummy", destination_root: "/plugin/root")

    plugin_builder.generate_test_dummy(true)

    invoke_call = generator.calls.find { |name,| name == :invoke }
    assert_equal Rails::Generators::AppGenerator, invoke_call[1][0]
    assert_equal ["/plugin/root/test/dummy"], invoke_call[1][1]

    invoke_options = invoke_call[1][2]
    assert_equal "sqlite3", invoke_options[:database]
    assert_equal true, invoke_options[:force]
    assert_equal true, invoke_options[:dummy_app]
    assert_equal true, invoke_options[:skip_bundle]
    assert_equal true, invoke_options[:skip_ci]
    assert_equal true, invoke_options[:skip_git]
    assert_equal true, invoke_options[:skip_hotwire]
    assert_equal true, invoke_options[:skip_rubocop]
    assert_equal true, invoke_options[:skip_thruster]
    assert_not invoke_options.key?(:dev)
    assert_not invoke_options.key?(:edge)
    assert_not invoke_options.key?(:template)
  end

  test "gemfile_entry appends a path entry only inside an application with a Gemfile" do
    Dir.mktmpdir do |app_path|
      File.write(File.join(app_path, "Gemfile"), "source \"https://rubygems.org\"\n")
      plugin_builder, generator = builder({}, inside_application?: true, rails_app_path: app_path, name: "bukkits", relative_path: "plugins/bukkits")

      plugin_builder.gemfile_entry

      assert_includes generator.calls, [:append_file, [File.join(app_path, "Gemfile"), "\ngem \"bukkits\", path: \"plugins/bukkits\""], {}]
    end

    outside_builder, outside_generator = builder({}, inside_application?: false)
    outside_builder.gemfile_entry

    assert_equal [[:inside_application?, [], {}]], outside_generator.calls

    Dir.mktmpdir do |app_path|
      missing_gemfile_builder, missing_gemfile_generator = builder({}, inside_application?: true, rails_app_path: app_path)
      missing_gemfile_builder.gemfile_entry

      assert_equal [[:inside_application?, [], {}], [:rails_app_path, [], {}]], missing_gemfile_generator.calls
    end
  end

  test "stylesheets creates mountable asset file or full engine asset directory" do
    mountable_builder, mountable_generator = builder({}, mountable?: true, full?: false, namespaced_name: "bukkits")
    mountable_builder.stylesheets

    assert_equal [
      [:mountable?, [], {}],
      [:namespaced_name, [], {}],
      [:copy_file, ["rails/stylesheets.css", "app/assets/stylesheets/bukkits/application.css"], {}]
    ], mountable_generator.calls

    full_builder, full_generator = builder({}, mountable?: false, full?: true, namespaced_name: "bukkits")
    full_builder.stylesheets

    assert_equal [
      [:mountable?, [], {}],
      [:full?, [], {}],
      [:namespaced_name, [], {}],
      [:empty_directory_with_keep_file, ["app/assets/stylesheets/bukkits"], {}]
    ], full_generator.calls

    plain_builder, plain_generator = builder({}, mountable?: false, full?: false)
    plain_builder.stylesheets

    assert_equal [[:mountable?, [], {}], [:full?, [], {}]], plain_generator.calls
  end

  test "test helper creates common test files and engine-only directories" do
    plain_builder, plain_generator = builder({}, engine?: false)
    plain_builder.test

    assert_equal [
      [:template, ["test/test_helper.rb"], {}],
      [:template, ["test/%namespaced_name%_test.rb"], {}],
      [:engine?, [], {}]
    ], plain_generator.calls

    engine_builder, engine_generator = builder({}, engine?: true, api?: false)
    engine_builder.test

    assert_equal [
      [:template, ["test/test_helper.rb"], {}],
      [:template, ["test/%namespaced_name%_test.rb"], {}],
      [:engine?, [], {}],
      [:empty_directory_with_keep_file, ["test/fixtures/files"], {}],
      [:empty_directory_with_keep_file, ["test/controllers"], {}],
      [:empty_directory_with_keep_file, ["test/mailers"], {}],
      [:empty_directory_with_keep_file, ["test/models"], {}],
      [:empty_directory_with_keep_file, ["test/integration"], {}],
      [:api?, [], {}],
      [:empty_directory_with_keep_file, ["test/helpers"], {}],
      [:template, ["test/integration/navigation_test.rb"], {}]
    ], engine_generator.calls

    api_engine_builder, api_engine_generator = builder({}, engine?: true, api?: true)
    api_engine_builder.test

    assert_not_includes api_engine_generator.calls, [:empty_directory_with_keep_file, ["test/helpers"], {}]
    assert_includes api_engine_generator.calls, [:template, ["test/integration/navigation_test.rb"], {}]
  end

  test "test dummy config customizes boot routes and helper configuration" do
    mountable_builder, mountable_generator = builder({}, dummy_path: "test/dummy", mountable?: true, engine?: true, api?: false)
    mountable_builder.test_dummy_config

    assert_includes mountable_generator.calls, [:template, ["rails/boot.rb", "test/dummy/config/boot.rb"], { force: true }]
    assert_includes mountable_generator.calls, [:template, ["rails/routes.rb", "test/dummy/config/routes.rb"], { force: true }]
    assert_equal 1, mountable_generator.calls.count { |name,| name == :insert_into_file }

    api_engine_builder, api_engine_generator = builder({}, dummy_path: "test/dummy", mountable?: false, engine?: true, api?: true)
    api_engine_builder.test_dummy_config

    assert_includes api_engine_generator.calls, [:template, ["rails/boot.rb", "test/dummy/config/boot.rb"], { force: true }]
    assert_not_includes api_engine_generator.calls, [:template, ["rails/routes.rb", "test/dummy/config/routes.rb"], { force: true }]
    assert_empty api_engine_generator.calls.select { |name,| name == :insert_into_file }
  end

  test "test dummy assets and cleanup touch dummy application paths" do
    plugin_builder, generator = builder({}, dummy_path: "test/dummy")

    plugin_builder.test_dummy_assets
    plugin_builder.test_dummy_clean

    assert_includes generator.calls, [:template, ["rails/stylesheets.css", "test/dummy/app/assets/stylesheets/application.css"], { force: true }]
    assert_includes generator.calls, [:inside, ["test/dummy"], {}]
    assert_includes generator.calls, [:remove_file, [".ruby-version"], {}]
    assert_includes generator.calls, [:remove_dir, ["db"], {}]
    assert_includes generator.calls, [:remove_file, ["Gemfile"], {}]
    assert_includes generator.calls, [:remove_dir, ["lib"], {}]
    assert_includes generator.calls, [:remove_file, ["public/robots.txt"], {}]
    assert_includes generator.calls, [:remove_file, ["README.md"], {}]
    assert_includes generator.calls, [:remove_file, ["test"], {}]
    assert_includes generator.calls, [:remove_file, ["vendor"], {}]
  end

  test "version_control initializes git only when not skipped or pretending" do
    plugin_builder, generator = builder({ skip_git: false, pretend: false, quiet: true }, git_init_command: "git init --initial-branch=main")
    plugin_builder.version_control

    assert_equal [
      [:git_init_command, [], {}],
      [:run, ["git init --initial-branch=main"], { capture: true, abort_on_failure: false }]
    ], generator.calls

    skipped_builder, skipped_generator = builder({ skip_git: true, pretend: false })
    skipped_builder.version_control

    assert_empty skipped_generator.calls

    pretend_builder, pretend_generator = builder({ skip_git: false, pretend: true })
    pretend_builder.version_control

    assert_empty pretend_generator.calls
  end
end
