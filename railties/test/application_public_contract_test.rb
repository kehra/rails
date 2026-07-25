# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"

module ApplicationPublicContractTestNamespace
  class Application < Rails::Application
  end
end

class ApplicationPublicContractTest < ActiveSupport::TestCase
  setup do
    @old_env = Rails.env
  end

  teardown do
    Rails.env = @old_env
  end

  test "create initializes variables evaluates block once and reports name and initialized state" do
    routes = ActionDispatch::Routing::RouteSet.new
    app = ApplicationPublicContractTestNamespace::Application.create(routes: routes) do
      config.secret_key_base = "contract-secret"
    end

    assert_same routes, app.routes
    assert_equal "application-public-contract-test-namespace", app.name
    assert_not_predicate app, :initialized?
    assert_same app, app.run_load_hooks!
  end

  test "find_root locates config.ru from nested paths" do
    Dir.mktmpdir("rails-application-root") do |root|
      File.write(File.join(root, "config.ru"), "run RackApp")
      nested = File.join(root, "app", "models")
      FileUtils.mkdir_p(nested)

      assert_equal Pathname.new(root), Rails::Application.find_root(nested)
    end
  end

  test "key generators message verifiers and deprecators are memoized public collaborators" do
    app = ApplicationPublicContractTestNamespace::Application.create
    app.config.secret_key_base = "contract-secret"

    assert_same app.key_generator, app.key_generator
    assert_not_same app.key_generator, app.key_generator("other-secret")
    assert_same app.message_verifiers, app.message_verifiers
    assert_same app.message_verifier(:signed), app.message_verifier(:signed)
    assert_instance_of ActiveSupport::Deprecation::Deprecators, app.deprecators
    assert_same Rails.deprecator, app.deprecators[:railties]
  end

  test "application instance runs load hooks and class inheritance registers app class" do
    klass = Class.new(Rails::Application)
    assert_equal klass, Rails.app_class

    app = klass.instance

    assert_same app, klass.instance
    assert app.instance_variable_get(:@ran_load_hooks)
  end

  test "eager load delegates to each Rails autoloader" do
    app = ApplicationPublicContractTestNamespace::Application.create
    loader = Class.new do
      attr_reader :eager_loaded

      def eager_load
        @eager_loaded = true
      end
    end.new
    singleton = class << Rails; self; end
    original_autoloaders = Rails.method(:autoloaders)
    singleton.define_method(:autoloaders) { [ loader ] }

    app.eager_load!

    assert loader.eager_loaded
  ensure
    singleton&.define_method(:autoloaders) { |*args, **kwargs, &block| original_autoloaders.call(*args, **kwargs, &block) }
  end

  test "envs dotenvs credentials encrypted and creds expose configuration backends" do
    app = ApplicationPublicContractTestNamespace::Application.create
    app.config.root = Pathname.new(Dir.mktmpdir("rails-application-config"))
    FileUtils.mkdir_p(app.config.root.join("config"))
    app.config.credentials.content_path = app.config.root.join("config/credentials.yml.enc")
    app.config.credentials.key_path = app.config.root.join("config/master.key")
    app.config.require_master_key = false

    assert_instance_of ActiveSupport::EnvConfiguration, app.envs
    assert_same app.envs, app.envs
    assert_instance_of ActiveSupport::DotEnvConfiguration, app.dotenvs(app.config.root.join(".env"))
    assert_instance_of ActiveSupport::EncryptedConfiguration, app.credentials
    assert_instance_of ActiveSupport::EncryptedConfiguration, app.encrypted("config/credentials.yml.enc")

    Rails.env = "development"
    app.creds = nil
    assert_instance_of ActiveSupport::CombinedConfiguration, app.creds
    Rails.env = "production"
    app.creds = nil
    assert_instance_of ActiveSupport::CombinedConfiguration, app.creds
  ensure
    FileUtils.rm_rf(app.config.root) if app&.config&.root&.to_s&.include?("rails-application-config")
  end

  test "env_config exposes action dispatch collaborators" do
    app = ApplicationPublicContractTestNamespace::Application.create
    app.config.secret_key_base = "contract-secret"
    app.config.consider_all_requests_local = true

    env_config = app.env_config

    assert_same env_config, app.env_config
    assert_equal app.config.filter_parameters, env_config["action_dispatch.parameter_filter"]
    assert_equal app.secret_key_base, env_config["action_dispatch.secret_key_base"]
    assert_equal Rails.backtrace_cleaner, env_config["action_dispatch.backtrace_cleaner"]
    assert_equal app.key_generator, env_config["action_dispatch.key_generator"]
    assert_nil env_config["action_dispatch.content_security_policy"]
    assert_nil env_config["action_dispatch.permissions_policy"]
  end

  test "config_for loads pathnames merges shared config and reports missing files" do
    app = ApplicationPublicContractTestNamespace::Application.create
    Dir.mktmpdir("rails-application-config-for") do |root|
      config_dir = Pathname.new(root).join("config")
      FileUtils.mkdir_p(config_dir)
      config_file = config_dir.join("custom.yml")
      config_file.write <<~YAML
        shared:
          nested:
            shared: true
        test:
          nested:
            env: true
      YAML
      app.config.paths["config"] = config_dir.to_s

      config = app.config_for(config_file, env: "test")
      assert_equal true, config.nested[:shared]
      assert_equal true, config.nested[:env]

      error = assert_raises(RuntimeError) { app.config_for(:missing, env: "test") }
      assert_match(/Could not load configuration/, error.message)
    end
  end

  test "config_for handles shared and non hash configuration shapes" do
    app = ApplicationPublicContractTestNamespace::Application.create
    Dir.mktmpdir("rails-application-config-for-shapes") do |root|
      config_dir = Pathname.new(root).join("config")
      FileUtils.mkdir_p(config_dir)
      app.config.paths["config"] = config_dir.to_s

      config_dir.join("shared_hash.yml").write <<~YAML
        shared:
          fallback: true
      YAML
      assert_equal true, app.config_for(:shared_hash, env: "missing").fallback

      config_dir.join("shared_array.yml").write <<~YAML
        shared:
          - fallback
      YAML
      assert_equal [ "fallback" ], app.config_for(:shared_array, env: "missing")

      config_dir.join("shared_and_env_arrays.yml").write <<~YAML
        shared:
          - fallback
        test:
          - env
      YAML
      assert_equal [ "env" ], app.config_for(:shared_and_env_arrays, env: "test")

      config_dir.join("env_array.yml").write <<~YAML
        test:
          - env
      YAML
      assert_equal [ "env" ], app.config_for(:env_array, env: "test")

      config_dir.join("env_string.yml").write <<~YAML
        test: value
      YAML
      assert_equal "value", app.config_for(:env_string, env: "test")

      config_dir.join("no_shared.yml").write <<~YAML
        test:
          value: true
      YAML
      assert_equal true, app.config_for(:no_shared, env: "test").value
    end
  end

  test "revision uses environment file git fallback and explicit assignment" do
    app = ApplicationPublicContractTestNamespace::Application.create
    original_revision = ENV.delete("REVISION")

    Dir.mktmpdir("rails-application-revision") do |root|
      app.config.root = Pathname.new(root)

      ENV["REVISION"] = "env-revision"
      assert_equal "env-revision", app.revision
      assert_equal "env-revision", app.revision

      ENV.delete("REVISION")
      app.instance_variable_set(:@revision, nil)
      app.instance_variable_set(:@revision_initialized, false)
      File.write(File.join(root, "REVISION"), "file-revision\n")
      assert_equal "file-revision", app.revision

      app.instance_variable_set(:@revision, nil)
      app.instance_variable_set(:@revision_initialized, false)
      File.delete(File.join(root, "REVISION"))
      system("git", "-C", root, "init", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "config", "user.email", "test@example.com", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "config", "user.name", "Test", out: File::NULL, err: File::NULL)
      File.write(File.join(root, "README.md"), "revision")
      system("git", "-C", root, "add", "README.md", out: File::NULL, err: File::NULL)
      system("git", "-C", root, "commit", "-m", "revision", out: File::NULL, err: File::NULL)
      assert_match(/\A\h{40}\z/, app.revision)

      app.instance_variable_set(:@revision, nil)
      app.instance_variable_set(:@revision_initialized, false)
      singleton = class << app; self; end
      original_system = app.method(:system)
      singleton.define_method(:system) { |*| false }
      assert_nil app.revision
      singleton.define_method(:system) { |*args, **kwargs, &block| original_system.call(*args, **kwargs, &block) }

      app.revision = :explicit
      assert_equal "explicit", app.revision
    end
  ensure
    if original_revision
      ENV["REVISION"] = original_revision
    else
      ENV.delete("REVISION")
    end
  end

  test "reload_routes always delegates to reload" do
    app = ApplicationPublicContractTestNamespace::Application.create
    reloader = RoutesReloaderFake.new
    app.instance_variable_set(:@routes_reloader, reloader)

    app.reload_routes!

    assert reloader.reloaded
  end

  test "callback registration helpers delegate to the application class" do
    klass = Class.new(Rails::Application)
    app = klass.create
    block = proc { }

    assert_nothing_raised do
      app.rake_tasks(&block)
      app.runner(&block)
      app.console(&block)
      app.generators(&block)
      app.server(&block)
      app.initializer(:contract_initializer, &block)
    end
    assert klass.initializers.has?(:contract_initializer)
  end

  test "isolate namespace delegates to the application class" do
    mod = ApplicationPublicContractTestNamespace.const_set(:IsolatedNamespace, Module.new)
    klass = Class.new(Rails::Application)
    app = klass.create

    app.isolate_namespace(mod)

    assert_equal klass, mod.railtie_namespace
  ensure
    ApplicationPublicContractTestNamespace.send(:remove_const, :IsolatedNamespace) if ApplicationPublicContractTestNamespace.const_defined?(:IsolatedNamespace, false)
  end

  RoutesReloaderFake = Struct.new(:reloaded)

  class RoutesReloaderFake
    def reload!
      self.reloaded = true
    end
  end
end
