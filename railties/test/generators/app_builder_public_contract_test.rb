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

  test "config when updating preserves existing update-sensitive files and restores missing defaults" do
    app = Struct.new(:config).new(Struct.new(:loaded_config_version).new("7.1"))

    Dir.mktmpdir("app-builder-config-update") do |root|
      Dir.chdir(root) do
        with_rails_application(app) do
          missing_defaults = builder({ update: true, api: true }, skip_asset_pipeline?: true)
          missing_defaults.config_when_updating

          missing_calls = missing_defaults.instance_variable_get(:@generator).calls
          assert_includes missing_calls, [:template, ["config/cable.yml"], {}]
          assert_includes missing_calls, [:template, ["config/storage.yml"], {}]
          assert_includes missing_calls, [:template, ["config/ci.rb"], {}]
          assert_includes missing_calls, [:remove_file, ["config/initializers/assets.rb"], {}]
          assert_includes missing_calls, [:remove_file, ["app/assets/stylesheets/application.css"], {}]
          assert_includes missing_calls, [:remove_file, ["config/initializers/cors.rb"], {}]
          assert_includes missing_calls, [:template, ["config/bundler-audit.yml"], {}]
          assert_includes missing_calls, [:remove_file, ["config/initializers/content_security_policy.rb"], {}]
          assert_equal "7.1", missing_defaults.instance_variable_get(:@config_target_version)

          %w[
            config/cable.yml config/storage.yml config/ci.rb config/bundler-audit.yml
            config/initializers/cors.rb config/initializers/assets.rb
            app/assets/stylesheets/application.css config/initializers/content_security_policy.rb
          ].each do |path|
            FileUtils.mkdir_p(File.dirname(path))
            File.write(path, "existing")
          end

          existing_files = builder({ update: true, api: true }, skip_asset_pipeline?: true)
          existing_files.config_when_updating
          existing_calls = existing_files.instance_variable_get(:@generator).calls
          refute_includes existing_calls, [:template, ["config/cable.yml"], {}]
          refute_includes existing_calls, [:template, ["config/storage.yml"], {}]
          refute_includes existing_calls, [:template, ["config/ci.rb"], {}]
          refute_includes existing_calls, [:remove_file, ["config/initializers/assets.rb"], {}]
          refute_includes existing_calls, [:remove_file, ["app/assets/stylesheets/application.css"], {}]
          refute_includes existing_calls, [:remove_file, ["config/initializers/cors.rb"], {}]
          refute_includes existing_calls, [:template, ["config/bundler-audit.yml"], {}]
          refute_includes existing_calls, [:remove_file, ["config/initializers/content_security_policy.rb"], {}]

          non_api = builder({ update: true, api: false }, skip_asset_pipeline?: true)
          non_api.config_when_updating
          refute_includes non_api.instance_variable_get(:@generator).calls, [:remove_file, ["config/initializers/content_security_policy.rb"], {}]
        end
      end
    end
  end

  test "config target version falls back to the current rails version" do
    assert_equal Rails::VERSION::STRING.to_f, builder.config_target_version
  end

  private
    def with_rails_application(application)
      singleton = class << Rails; self; end
      original = Rails.method(:application)
      singleton.define_method(:application) { application }
      yield
    ensure
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_singleton_method(object, name, replacement)
      singleton = object.singleton_class
      original = object.method(name)
      singleton.define_method(name, &replacement)
      yield
    ensure
      singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end

class AppGeneratorPublicContractTest < ActiveSupport::TestCase
  def app_generator(options = {}, responses = {})
    generator = Rails::Generators::AppGenerator.allocate
    calls = []
    generator.instance_variable_set(:@after_bundle_callbacks, [])
    generator.define_singleton_method(:calls) { calls }
    generator.define_singleton_method(:options) { options }
    generator.define_singleton_method(:build) { |name, *args| calls << [:build, name, args] }
    generator.define_singleton_method(:template) { |*args, **kwargs| calls << [:template, args, kwargs] }
    generator.define_singleton_method(:remove_dir) { |*args| calls << [:remove_dir, args] }
    generator.define_singleton_method(:remove_file) { |*args| calls << [:remove_file, args] }
    generator.define_singleton_method(:create_file) { |*args| calls << [:create_file, args] }
    generator.define_singleton_method(:rails_command) { |*args, **kwargs| calls << [:rails_command, args, kwargs] }

    %i[
      using_node? skip_active_storage? skip_docker? skip_rubocop? skip_ci?
      skip_storage? skip_devcontainer? skip_asset_pipeline?
    ].each do |predicate|
      generator.define_singleton_method(predicate) { responses.fetch(predicate, false) }
    end

    generator
  end

  test "initialize applies implied options and prepares after bundle callbacks" do
    destination = Dir.mktmpdir("app-generator-initialize")
    generator = Rails::Generators::AppGenerator.new([destination], { minimal: true }, destination_root: destination)

    assert_equal [], generator.instance_variable_get(:@after_bundle_callbacks)
    assert_equal true, generator.options[:skip_action_cable]
  ensure
    FileUtils.rm_rf(destination) if destination
  end

  test "create root files builds root-level pieces with option gates" do
    generator = app_generator({ skip_git: false }, using_node?: true)

    generator.create_root_files

    assert_equal [
      [:build, :readme, []],
      [:build, :rakefile, []],
      [:build, :node_version, []],
      [:build, :ruby_version, []],
      [:build, :configru, []],
      [:build, :gitignore, []],
      [:build, :gitattributes, []],
      [:build, :gemfile, []],
      [:build, :version_control, []]
    ], generator.calls

    skipped = app_generator({ skip_git: true }, using_node?: false)
    skipped.create_root_files
    refute_includes skipped.calls, [:build, :node_version, []]
    refute_includes skipped.calls, [:build, :gitignore, []]
    refute_includes skipped.calls, [:build, :gitattributes, []]
  end

  test "create methods delegate to matching app builder steps" do
    generator = app_generator({}, skip_active_storage?: false, skip_docker?: false, skip_rubocop?: false, skip_ci?: false, skip_storage?: false, skip_devcontainer?: false)

    generator.create_app_files
    generator.create_bin_files
    generator.update_bin_files
    generator.update_active_storage
    generator.create_dockerfiles
    generator.create_rubocop_file
    generator.create_cifiles
    generator.create_config_files
    generator.update_config_files
    generator.create_master_key
    generator.create_creds
    generator.create_boot_file
    generator.create_active_record_files
    generator.create_db_files
    generator.create_lib_files
    generator.create_log_files
    generator.create_public_files
    generator.create_script_folder
    generator.create_tmp_files
    generator.create_vendor_files
    generator.create_test_files
    generator.create_system_test_files
    generator.create_storage_files
    generator.create_devcontainer_files
    generator.finish_template

    assert_includes generator.calls, [:build, :app, []]
    assert_includes generator.calls, [:build, :bin, []]
    assert_includes generator.calls, [:build, :bin_when_updating, []]
    assert_includes generator.calls, [:rails_command, ["active_storage:update"], { inline: true }]
    assert_includes generator.calls, [:build, :dockerfiles, []]
    assert_includes generator.calls, [:build, :rubocop, []]
    assert_includes generator.calls, [:build, :cifiles, []]
    assert_includes generator.calls, [:build, :config, []]
    assert_includes generator.calls, [:build, :config_when_updating, []]
    assert_includes generator.calls, [:build, :master_key, []]
    assert_includes generator.calls, [:build, :env, []]
    assert_includes generator.calls, [:build, :credentials, []]
    assert_includes generator.calls, [:build, :credentials_diff_enroll, []]
    assert_includes generator.calls, [:build, :database_yml, []]
    assert_includes generator.calls, [:build, :db, []]
    assert_includes generator.calls, [:build, :lib, []]
    assert_includes generator.calls, [:build, :log, []]
    assert_includes generator.calls, [:build, :public_directory, []]
    assert_includes generator.calls, [:build, :script, []]
    assert_includes generator.calls, [:build, :tmp, []]
    assert_includes generator.calls, [:build, :vendor, []]
    assert_includes generator.calls, [:build, :test, []]
    assert_includes generator.calls, [:build, :system_test, []]
    assert_includes generator.calls, [:build, :storage, []]
    assert_includes generator.calls, [:build, :devcontainer, []]
    assert_includes generator.calls, [:build, :leftovers, []]
    assert_includes generator.calls, [:template, ["config/boot.rb"], {}]
  end

  test "create methods honor skip options" do
    generator = app_generator({ skip_active_record: true, skip_test: true, dummy_app: true },
      skip_active_storage?: true, skip_docker?: true, skip_rubocop?: true, skip_ci?: true, skip_storage?: true, skip_devcontainer?: true)

    generator.update_active_storage
    generator.create_dockerfiles
    generator.create_rubocop_file
    generator.create_cifiles
    generator.create_active_record_files
    generator.create_db_files
    generator.create_script_folder
    generator.create_test_files
    generator.create_storage_files
    generator.create_devcontainer_files

    assert_empty generator.calls
  end

  test "delete methods remove files only when matching options are enabled" do
    generator = app_generator({ api: true, skip_action_mailer: true, skip_active_record: true, skip_active_job: true, skip_action_cable: true, update: false },
      skip_asset_pipeline?: true)

    generator.delete_app_assets_if_api_option
    generator.delete_app_helpers_if_api_option
    generator.delete_app_views_if_api_option
    generator.delete_public_files_if_api_option
    generator.delete_assets_initializer_skipping_asset_pipeline
    generator.delete_application_record_skipping_active_record
    generator.delete_active_job_folder_if_skipping_active_job
    generator.delete_action_mailer_files_skipping_action_mailer
    generator.delete_action_cable_files_skipping_action_cable
    generator.delete_non_api_initializers_if_api_option
    generator.delete_api_initializers
    generator.delete_new_framework_defaults

    assert_includes generator.calls, [:remove_dir, ["app/assets"]]
    assert_includes generator.calls, [:remove_dir, ["app/helpers"]]
    assert_includes generator.calls, [:remove_dir, ["test/helpers"]]
    assert_includes generator.calls, [:remove_dir, ["app/views"]]
    assert_includes generator.calls, [:remove_file, ["public/400.html"]]
    assert_includes generator.calls, [:remove_file, ["config/initializers/assets.rb"]]
    assert_includes generator.calls, [:remove_file, ["app/models/application_record.rb"]]
    assert_includes generator.calls, [:remove_dir, ["app/jobs"]]
    assert_includes generator.calls, [:remove_dir, ["app/mailers"]]
    assert_includes generator.calls, [:remove_dir, ["app/javascript/channels"]]
    assert_includes generator.calls, [:remove_file, ["config/initializers/content_security_policy.rb"]]
    refute_includes generator.calls, [:remove_file, ["config/initializers/cors.rb"]]
    assert generator.calls.any? { |call| call == [:remove_file, ["config/initializers/new_framework_defaults_#{Rails::VERSION::MAJOR}_#{Rails::VERSION::MINOR}.rb"]] }
  end

  test "delete methods are no-ops when matching options are disabled" do
    generator = app_generator({ api: false, skip_active_record: false, skip_active_job: false, skip_action_mailer: false, skip_action_cable: false, update: true },
      skip_asset_pipeline?: false)

    generator.delete_app_assets_if_api_option
    generator.delete_app_helpers_if_api_option
    generator.delete_app_views_if_api_option
    generator.delete_public_files_if_api_option
    generator.delete_assets_initializer_skipping_asset_pipeline
    generator.delete_application_record_skipping_active_record
    generator.delete_active_job_folder_if_skipping_active_job
    generator.delete_action_mailer_files_skipping_action_mailer
    generator.delete_action_cable_files_skipping_action_cable
    generator.delete_non_api_initializers_if_api_option

    assert_empty generator.calls
  end

  test "delete app views keeps mailer layout when api app keeps action mailer" do
    generator = app_generator({ api: true, skip_action_mailer: false, update: true, skip_active_record: false, skip_active_job: false },
      skip_asset_pipeline?: true)

    generator.delete_app_views_if_api_option
    generator.delete_new_framework_defaults

    assert_includes generator.calls, [:remove_file, ["app/views/layouts/application.html.erb"]]
    assert_includes generator.calls, [:remove_dir, ["app/views/pwa"]]
    refute generator.calls.any? { |call| call == [:remove_file, ["config/initializers/new_framework_defaults_#{Rails::VERSION::MAJOR}_#{Rails::VERSION::MINOR}.rb"]] }

    non_api = app_generator({ api: false }, skip_asset_pipeline?: true)
    non_api.delete_assets_initializer_skipping_asset_pipeline
    non_api.delete_api_initializers

    assert_includes non_api.calls, [:create_file, ["app/assets/stylesheets/application.css", "/* Application styles */\n"]]
    assert_includes non_api.calls, [:remove_file, ["config/initializers/cors.rb"]]
  end

  test "callbacks and banner expose public app generator contract" do
    generator = app_generator
    ran = false
    generator.instance_variable_set(:@after_bundle_callbacks, [-> { ran = true }])

    generator.run_after_bundle_callbacks

    assert ran
    assert_match(/rails new APP_PATH \[options\]/, Rails::Generators::AppGenerator.banner)
  end
end
