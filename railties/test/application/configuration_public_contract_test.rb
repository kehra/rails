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
