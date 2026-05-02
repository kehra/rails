# frozen_string_literal: true

require "abstract_unit"
require "rails/application/configuration"

class ApplicationConfigurationPublicContractTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("rails-configuration-public-contract"))
    @config = Rails::Application::Configuration.new(@root)
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "initializes application defaults and appends application specific paths" do
    assert_equal Encoding::UTF_8, @config.encoding
    assert_equal false, @config.api_only
    assert_equal :debug, @config.log_level
    assert_equal [ :file_store, "#{@root}/tmp/cache/" ], @config.cache_store
    assert_equal [ :all ], @config.railties_order
    assert_equal "index", @config.public_file_server.index_name
    assert_equal "#{@root}/config/database.yml", @config.paths["config/database"].first
    assert_equal "#{@root}/config/environment.rb", @config.paths["config/environment"].first
    assert_equal "#{@root}/log/#{Rails.env}.log", @config.paths["log"].first
  end

  test "initializes development hosts from built in and environment hosts" do
    original_env = Rails.env
    original_development_hosts = ENV["RAILS_DEVELOPMENT_HOSTS"]
    Rails.env = "development"
    ENV["RAILS_DEVELOPMENT_HOSTS"] = "dev.example.test, api.example.test"

    config = Rails::Application::Configuration.new(@root)

    assert_includes config.hosts, "dev.example.test"
    assert_includes config.hosts, "api.example.test"
  ensure
    Rails.env = original_env
    ENV["RAILS_DEVELOPMENT_HOSTS"] = original_development_hosts
  end

  test "boolean reloading helpers invert cache_classes" do
    @config.cache_classes = false
    assert @config.enable_reloading
    assert @config.reloading_enabled?

    @config.enable_reloading = false
    assert @config.cache_classes
    assert_not @config.enable_reloading
  end

  test "api only enables generator mode and api exception responses" do
    @config.api_only = true

    assert @config.api_only
    assert @config.generators.api_only
    assert_equal :api, @config.debug_exception_response_format

    @config.debug_exception_response_format = :default
    @config.api_only = true
    assert_equal :default, @config.debug_exception_response_format
  end

  test "logging color and log level writers update collaborators" do
    original_colorize_logging = ActiveSupport.colorize_logging

    @config.colorize_logging = false
    assert_equal false, @config.colorize_logging
    assert_equal false, @config.generators.colorize_logging

    @config.log_level = :warn
    assert_equal :warn, @config.log_level
    assert_equal :warn, @config.broadcast_log_level
  ensure
    ActiveSupport.colorize_logging = original_colorize_logging
  end

  test "encoding writer updates Ruby default encodings" do
    original_external = Encoding.default_external
    original_internal = Encoding.default_internal

    @config.encoding = Encoding::US_ASCII

    assert_equal Encoding::US_ASCII, @config.encoding
    assert_equal Encoding::US_ASCII, Encoding.default_external
    assert_equal Encoding::US_ASCII, Encoding.default_internal
  ensure
    Encoding.default_external = original_external
    Encoding.default_internal = original_internal
  end

  test "policy helpers return nil until configured and build policies with blocks" do
    assert_nil @config.content_security_policy
    assert_nil @config.permissions_policy

    content_security_policy = @config.content_security_policy do |policy|
      policy.default_src :self
    end
    permissions_policy = @config.permissions_policy do |policy|
      policy.camera :none
    end

    assert_same content_security_policy, @config.content_security_policy
    assert_same permissions_policy, @config.permissions_policy
  end

  test "autoload lib helpers append lib paths and delegate ignores to matching autoloaders" do
    main_loader = Loader.new
    once_loader = Loader.new
    with_autoloaders(main: main_loader, once: once_loader) do
      @config.autoload_lib(ignore: [ "assets", "tasks" ])
      @config.autoload_lib_once(ignore: "generators")
    end

    assert_includes @config.autoload_paths, "#{@root}/lib"
    assert_includes @config.autoload_once_paths, "#{@root}/lib"
    assert_includes @config.eager_load_paths, "#{@root}/lib"
    assert_equal [ @root.join("lib/assets"), @root.join("lib/tasks") ], main_loader.ignored
    assert_equal [ @root.join("lib/generators") ], once_loader.ignored
  end

  test "default log file creates log directory and applies autoflush setting" do
    @config.autoflush_log = false

    log = @config.default_log_file
    log.write("contract")
    second_log = @config.default_log_file

    assert_equal @root.join("log/#{Rails.env}.log").to_s, log.path
    assert_equal log.path, second_log.path
    assert File.directory?(@root.join("log"))
    assert log.binmode?
    assert_not log.sync
  ensure
    log&.close
    second_log&.close
  end

  test "session store stores options resolves symbols and supports disabled sessions" do
    @config.session_store :cookie_store, key: "_contract_session", same_site: :lax

    assert_equal ActionDispatch::Session::CookieStore, @config.session_store
    assert_equal({ key: "_contract_session", same_site: :lax }, @config.session_options)
    assert_equal :cookie_store, @config.session_store?

    @config.session_store :disabled
    assert_nil @config.session_store

    custom_store = Class.new
    @config.session_store custom_store
    assert_equal custom_store, @config.session_store
  end

  test "secret key base resolves environment credentials local dummy and validates assignments" do
    application = Object.new
    credentials = Struct.new(:secret_key_base).new("credential-secret")
    application.define_singleton_method(:credentials) { credentials }

    original_env = Rails.env
    original_secret_key_base = ENV["SECRET_KEY_BASE"]
    original_secret_key_base_dummy = ENV["SECRET_KEY_BASE_DUMMY"]
    with_application(application) do
      Rails.env = "production"
      ENV["SECRET_KEY_BASE"] = "environment-secret"
      @config.instance_variable_set(:@secret_key_base, nil)
      assert_equal "environment-secret", @config.secret_key_base

      ENV.delete("SECRET_KEY_BASE")
      @config.instance_variable_set(:@secret_key_base, nil)
      assert_equal "credential-secret", @config.secret_key_base

      Rails.env = "development"
      ENV["SECRET_KEY_BASE_DUMMY"] = "1"
      @config.instance_variable_set(:@secret_key_base, nil)
      local_secret = @config.secret_key_base
      assert_match(/\A[0-9a-f]{128}\z/, local_secret)
      @config.instance_variable_set(:@secret_key_base, nil)
      assert_equal local_secret, @config.secret_key_base

      ENV.delete("SECRET_KEY_BASE_DUMMY")
      credentials.secret_key_base = nil
      @config.instance_variable_set(:@secret_key_base, nil)
      assert_equal local_secret, @config.secret_key_base

      @config.secret_key_base = nil
      assert_match(/\A[0-9a-f]{128}\z/, @config.secret_key_base)

      assert_raises(ArgumentError) { @config.secret_key_base = :invalid }
      assert_raises(ArgumentError) do
        Rails.env = "production"
        @config.secret_key_base = nil
      end
    end
  ensure
    Rails.env = original_env
    ENV["SECRET_KEY_BASE"] = original_secret_key_base
    ENV["SECRET_KEY_BASE_DUMMY"] = original_secret_key_base_dummy
  end

  test "annotations and revision writer delegate to public collaborators" do
    application = Object.new
    class << application
      attr_accessor :revision
    end

    with_application(application) do
      assert_equal Rails::SourceAnnotationExtractor::Annotation, @config.annotations
      @config.revision = :abc123
    end

    assert_equal :abc123, application.revision
  end

  private
    class Loader
      attr_reader :ignored

      def initialize
        @ignored = []
      end

      def ignore(paths)
        @ignored.concat(Array(paths))
      end
    end

    def with_autoloaders(main:, once:)
      autoloaders = Struct.new(:main, :once).new(main, once)
      singleton = class << Rails; self; end
      original = Rails.method(:autoloaders)
      singleton.define_method(:autoloaders) { autoloaders }
      yield
    ensure
      singleton.define_method(:autoloaders) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_application(application)
      singleton = class << Rails; self; end
      original = Rails.method(:application)
      singleton.define_method(:application) { application }
      yield
    ensure
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
