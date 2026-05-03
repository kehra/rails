# frozen_string_literal: true

require "abstract_unit"
require "rails/generators/rails/app/app_generator"
require "rails/generators/rails/master_key/master_key_generator"
require "rails/generators/rails/credentials/credentials_generator"

class AppBuilderPublicContractTest < ActiveSupport::TestCase
  class RecordingShell
    def mute
      yield
    end
  end

  class RecordingGeneratedCommand
    attr_reader :calls

    def initialize
      @calls = []
    end

    def add_master_key_file_silently
      calls << :add_master_key_file_silently
    end

    def add_credentials_file
      calls << :add_credentials_file
    end

    def invoke_all
      calls << :invoke_all
    end
  end

  class RecordingGenerator
    attr_reader :calls, :options

    def initialize(options = {}, responses = {})
      @options = options
      @responses = responses
      @calls = []
    end

    def method_missing(name, *args, **kwargs, &block)
      calls << [name, args, kwargs]
      block.call("content") if block
      @responses[name]
    end

    def respond_to_missing?(name, include_private = false)
      true
    end
  end

  def builder(options = {}, responses = {})
    Rails::AppBuilder.include(Rails::ActionMethods)
    Rails::AppBuilder.new(RecordingGenerator.new(options, responses))
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

  test "bin and docker helpers generate executable-aware files" do
    builder = builder()

    builder.bin
    builder.bin_when_updating
    builder.dockerfiles

    calls = builder.instance_variable_get(:@generator).calls
    actions = calls.reject { |name,| name.to_s.end_with?("?") || name == :shebang }

    assert_equal :directory, actions[0].first
    assert_equal ["bin", { exclude_pattern: Regexp.union([]) }], actions[0][1]
    assert_equal [:chmod, ["bin", 0755 & ~File.umask], { verbose: false }], actions[1]
    assert_equal :directory, actions[2].first
    assert_equal [:chmod, ["bin", 0755 & ~File.umask], { verbose: false }], actions[3]
    assert_includes calls, [:template, ["Dockerfile"], {}]
    assert_includes calls, [:template, ["dockerignore", ".dockerignore"], {}]
    assert_includes calls, [:template, ["docker-entrypoint", "bin/docker-entrypoint"], {}]
    assert_includes calls, [:chmod, ["bin/docker-entrypoint", 0755 & ~File.umask], { verbose: false }]
  end

  test "bin excludes optional executables when their features are skipped" do
    builder = builder({}, skip_thruster?: true, skip_rubocop?: true, skip_brakeman?: true, skip_bundler_audit?: true)

    builder.bin

    directory_call = builder.instance_variable_get(:@generator).calls.find { |name,| name == :directory }
    pattern = directory_call[1][1][:exclude_pattern]
    assert_match pattern, "thrust"
    assert_match pattern, "rubocop"
    assert_match pattern, "brakeman"
    assert_match pattern, "bundler-audit"
  end

  test "cifiles creates workflow directory and templates" do
    builder = builder()

    builder.cifiles

    assert_equal [
      [:empty_directory, [".github/workflows"], {}],
      [:template, ["github/ci.yml", ".github/workflows/ci.yml"], {}],
      [:template, ["github/dependabot.yml", ".github/dependabot.yml"], {}]
    ], builder.instance_variable_get(:@generator).calls
  end

  test "version control runs git init unless skipped or pretending" do
    builder = builder({}, git_init_command: "git init")
    builder.version_control

    assert_includes builder.instance_variable_get(:@generator).calls, [:run, ["git init"], { capture: nil, abort_on_failure: false }]

    skipped = builder(skip_git: true, git_init_command: "git init")
    skipped.version_control
    assert_empty skipped.instance_variable_get(:@generator).calls.grep([:run, ["git init"], { capture: nil, abort_on_failure: false }])
  end

  test "config skips update-sensitive templates when updating with skipped frameworks" do
    builder = builder({ update: true }, skip_bundler_audit?: true, skip_action_cable?: true, skip_active_storage?: true)

    builder.config

    calls = builder.instance_variable_get(:@generator).calls
    refute_includes calls, [:template, ["routes.rb"], {}]
    refute_includes calls, [:template, ["bundler-audit.yml"], {}]
    refute_includes calls, [:template, ["cable.yml"], {}]
    refute_includes calls, [:template, ["storage.yml"], {}]
    refute_includes calls, [:directory, ["locales"], {}]
  end

  test "config-related helpers delegate conditional templates and removals" do
    database = Struct.new(:template).new("config/databases/sqlite3.yml")
    builder = builder({}, database: database)

    builder.config
    builder.database_yml
    builder.public_directory

    calls = builder.instance_variable_get(:@generator).calls
    assert_includes calls, [:empty_directory, ["config"], {}]
    assert_includes calls, [:template, ["routes.rb"], {}]
    assert_includes calls, [:template, ["application.rb"], {}]
    assert_includes calls, [:template, ["environment.rb"], {}]
    assert_includes calls, [:template, ["bundler-audit.yml"], {}]
    assert_includes calls, [:template, ["cable.yml"], {}]
    assert_includes calls, [:template, ["ci.rb"], {}]
    assert_includes calls, [:template, ["puma.rb"], {}]
    assert_includes calls, [:template, ["storage.yml"], {}]
    assert_includes calls, [:directory, ["environments"], {}]
    assert_includes calls, [:directory, ["initializers"], {}]
    assert_includes calls, [:directory, ["locales"], {}]
    assert_includes calls, [:template, ["config/databases/sqlite3.yml", "config/database.yml"], {}]
    assert_includes calls, [:directory, ["public", "public"], { recursive: false }]
  end

  test "public directory is skipped for api updates" do
    builder = builder(update: true, api: true)

    assert_nil builder.public_directory
    assert_empty builder.instance_variable_get(:@generator).calls
  end

  test "system test files are created only when devcontainer needs system tests" do
    builder = builder({}, devcontainer?: true, depends_on_system_test?: true)

    builder.system_test

    assert_equal [
      [:empty_directory_with_keep_file, ["test/system"], {}],
      [:template, ["test/application_system_test_case.rb"], {}]
    ], builder.instance_variable_get(:@generator).calls.reject { |name,| name.to_s.end_with?("?") }
  end

  test "master key and credentials generators are skipped in pretend or dummy apps" do
    master_key = RecordingGeneratedCommand.new
    with_singleton_method(Rails::Generators::MasterKeyGenerator, :new, ->(*) { master_key }) do
      app_builder = builder(quiet: true, force: true)
      app_builder.master_key

      assert_equal [:add_master_key_file_silently], master_key.calls
    end

    credentials = RecordingGeneratedCommand.new
    with_singleton_method(Rails::Generators::CredentialsGenerator, :new, ->(*) { credentials }) do
      app_builder = builder
      app_builder.credentials

      assert_equal [:add_credentials_file], credentials.calls
    end

    [:pretend, :dummy_app].each do |option|
      skipped = builder(option => true)
      assert_nil skipped.master_key
      assert_nil skipped.credentials
    end
  end

  test "env file is skipped in pretend or dummy apps" do
    app_builder = builder
    app_builder.env
    assert_equal [[:template, ["env", ".env"], {}]], app_builder.instance_variable_get(:@generator).calls

    pretend = builder(pretend: true)
    assert_nil pretend.env
    assert_empty pretend.instance_variable_get(:@generator).calls

    dummy = builder(dummy_app: true)
    assert_nil dummy.env
    assert_empty dummy.instance_variable_get(:@generator).calls
  end

  test "credentials diff enrollment runs unless explicitly skipped" do
    shell = RecordingShell.new
    app_builder = builder({}, shell: shell)

    app_builder.credentials_diff_enroll

    assert_includes app_builder.instance_variable_get(:@generator).calls, [:rails_command, ["credentials:diff --enroll"], { inline: true, shell: shell }]

    [:skip_decrypted_diffs, :dummy_app, :pretend].each do |option|
      skipped = builder({ option => true }, shell: shell)
      assert_nil skipped.credentials_diff_enroll
      refute_includes skipped.instance_variable_get(:@generator).calls, [:rails_command, ["credentials:diff --enroll"], { inline: true, shell: shell }]
    end
  end

  test "devcontainer passes application options to the devcontainer generator" do
    devcontainer = RecordingGeneratedCommand.new
    captured = nil

    with_singleton_method(Rails::Generators::DevcontainerGenerator, :new, ->(args, options) { captured = [args, options]; devcontainer }) do
      app_builder = builder({ database: "sqlite3", skip_solid: true, skip_action_cable: false, skip_active_job: true, skip_kamal: false, skip_active_storage: false, dev: true, pretend: true },
        depends_on_system_test?: true,
        using_node?: true,
        app_name: "blog",
        app_path: "/tmp/blog")

      app_builder.devcontainer
    end

    assert_equal [], captured.first
    assert_equal({
      database: "sqlite3",
      redis: true,
      kamal: true,
      system_test: true,
      active_storage: true,
      dev: true,
      node: true,
      app_name: "blog",
      app_folder: "blog",
      skip_solid: true,
      pretend: true
    }, captured.last)
    assert_equal [:invoke_all], devcontainer.calls
  end

  test "devcontainer skips redis when solid, action cable, and active job are all skipped" do
    devcontainer = RecordingGeneratedCommand.new
    captured = nil

    with_singleton_method(Rails::Generators::DevcontainerGenerator, :new, ->(args, options) { captured = options; devcontainer }) do
      app_builder = builder({ database: "sqlite3", skip_solid: true, skip_action_cable: true, skip_active_job: true, skip_kamal: true, skip_active_storage: true, dev: false, pretend: false },
        depends_on_system_test?: false,
        using_node?: false,
        app_name: "api",
        app_path: "/tmp/api")

      app_builder.devcontainer
    end

    assert_equal false, captured[:redis]
    assert_equal false, captured[:kamal]
    assert_equal false, captured[:system_test]
    assert_equal false, captured[:active_storage]
    assert_equal false, captured[:node]
  end

  test "system test files are skipped when devcontainer does not need system tests" do
    builder = builder({}, devcontainer?: false, depends_on_system_test?: true)

    assert_nil builder.system_test
    assert_equal [[:devcontainer?, [], {}]], builder.instance_variable_get(:@generator).calls
  end

  test "config target version falls back to the current rails version" do
    assert_equal Rails::VERSION::STRING.to_f, builder.config_target_version
  end

  private
    def with_singleton_method(object, name, replacement)
      singleton = object.singleton_class
      original = object.method(name)
      singleton.define_method(name, &replacement)
      yield
    ensure
      singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
