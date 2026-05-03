# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"
require "stringio"
require "rack/runtime"

class ApplicationBootstrapPublicContractTest < ActiveSupport::TestCase
  setup do
    @old_logger = Rails.logger
    @old_cache = Rails.cache
    @old_cache_format_version = ActiveSupport.cache_format_version
  end

  teardown do
    Rails.logger = @old_logger
    Rails.cache = @old_cache
    ActiveSupport.cache_format_version = @old_cache_format_version
  end

  test "load active support honors bare mode and set eager load derives nil settings" do
    app = new_application
    app.config.active_support.bare = true
    run_bootstrap_initializer(app, :load_active_support)

    app.config.active_support.bare = false
    run_bootstrap_initializer(app, :load_active_support)

    app.config.eager_load = nil
    app.config.enable_reloading = false
    capture(:stderr) { run_bootstrap_initializer(app, :set_eager_load) }
    assert_equal true, app.config.eager_load

    app.config.eager_load = false
    run_bootstrap_initializer(app, :set_eager_load)
    assert_equal false, app.config.eager_load
  end

  test "initialize logger wraps configured logger and honors broadcast log level" do
    app = new_application
    app.config.logger = ActiveSupport::Logger.new(StringIO.new)
    app.config.log_level = :error
    Rails.logger = nil

    run_bootstrap_initializer(app, :initialize_logger)

    assert_instance_of ActiveSupport::BroadcastLogger, Rails.logger
    assert_equal ActiveSupport::Logger::ERROR, Rails.logger.level
  end

  test "initialize logger creates sized file logger applies levels and falls back to stderr" do
    app = new_application
    app.config.log_file_size = 1024
    app.config.log_level = :warn
    Rails.logger = nil

    run_bootstrap_initializer(app, :initialize_logger)

    assert_instance_of ActiveSupport::BroadcastLogger, Rails.logger
    assert_equal ActiveSupport::Logger::WARN, Rails.logger.level

    app.config.log_file_size = nil
    Rails.logger = nil
    run_bootstrap_initializer(app, :initialize_logger)
    assert_instance_of ActiveSupport::BroadcastLogger, Rails.logger

    app.config.log_level = :fatal
    Rails.logger = ActiveSupport::BroadcastLogger.new(ActiveSupport::Logger.new(StringIO.new))
    run_bootstrap_initializer(app, :initialize_logger)
    assert_equal ActiveSupport::Logger::FATAL, Rails.logger.level

    app.config.instance_variable_set(:@broadcast_log_level, nil)
    Rails.logger = ActiveSupport::BroadcastLogger.new(ActiveSupport::Logger.new(StringIO.new))
    run_bootstrap_initializer(app, :initialize_logger)
    assert_equal ActiveSupport::Logger::DEBUG, Rails.logger.level

    original_logger_new = ActiveSupport::Logger.method(:new)
    ActiveSupport::Logger.define_singleton_method(:new) do |target, *args, **kwargs|
      raise "no log file" unless target.equal?(STDERR)
      original_logger_new.call(target, *args, **kwargs)
    end
    app.config.log_level = :warn
    Rails.logger = nil

    run_bootstrap_initializer(app, :initialize_logger)

    assert_equal ActiveSupport::Logger::WARN, Rails.logger.level
  ensure
    ActiveSupport::Logger.define_singleton_method(:new) { |*args, **kwargs, &block| original_logger_new.call(*args, **kwargs, &block) } if original_logger_new
  end

  test "initialize cache applies cache format version and inserts cache middleware" do
    app = new_application
    cache = Class.new do
      def middleware = :cache_middleware
    end.new
    original_lookup_store = ActiveSupport::Cache.method(:lookup_store)
    ActiveSupport::Cache.define_singleton_method(:lookup_store) { |*| cache }
    app.config.active_support.cache_format_version = 7.1
    Rails.cache = nil

    run_bootstrap_initializer(app, :initialize_cache)

    assert_equal 7.1, ActiveSupport.cache_format_version
    assert_same cache, Rails.cache
    assert_not_empty app.config.middleware.instance_variable_get(:@operations)

    app.config.active_support.cache_format_version = nil
    Rails.cache = Object.new
    run_bootstrap_initializer(app, :initialize_cache)
    assert_kind_of Object, Rails.cache

    cache_without_middleware = Object.new
    ActiveSupport::Cache.define_singleton_method(:lookup_store) { |*| cache_without_middleware }
    Rails.cache = nil
    run_bootstrap_initializer(app, :initialize_cache)
    assert_same cache_without_middleware, Rails.cache
  ensure
    ActiveSupport::Cache.define_singleton_method(:lookup_store) { |*args, **kwargs, &block| original_lookup_store.call(*args, **kwargs, &block) }
  end

  test "initialize error and event reporters derive debug settings from app config" do
    app = new_application
    app.config.consider_all_requests_local = true
    app.config.log_level = :debug

    run_bootstrap_initializer(app, :initialize_logger)
    run_bootstrap_initializer(app, :initialize_error_reporter)
    run_bootstrap_initializer(app, :initialize_event_reporter)

    assert Rails.error.debug_mode
    assert Rails.event.instance_variable_get(:@debug_mode)
    assert Rails.event.instance_variable_get(:@raise_on_error)

    Rails.error.debug_mode = false
    app.config.consider_all_requests_local = false
    app.config.log_level = :info
    run_bootstrap_initializer(app, :initialize_error_reporter)
    run_bootstrap_initializer(app, :initialize_event_reporter)
    assert_same Rails.logger, Rails.error.logger
    assert_equal false, Rails.event.instance_variable_get(:@debug_mode)

    captured = []
    subscriber = Class.new do
      define_method(:report) do |error, handled:, severity:, context:, source:|
        captured << context
      end
    end.new
    Rails.error.subscribe(subscriber)
    Rails.error.report(StandardError.new("contract"), handled: true)
    assert_equal Rails::VERSION::STRING, captured.last[:rails][:version]
    assert_nil captured.last[:rails][:app_revision]
    assert_equal Rails.env.to_s, captured.last[:rails][:environment]
  ensure
    Rails.error.unsubscribe(subscriber) if subscriber
  end

  test "setup once autoloader registers existing unique paths and skips configured or missing paths" do
    app = new_application
    root = app.config.root
    eager_path = root.join("app/models").to_s
    lazy_path = root.join("app/services").to_s
    configured_path = root.join("app/configured").to_s
    missing_path = root.join("app/missing").to_s
    [ eager_path, lazy_path, configured_path ].each { |path| FileUtils.mkdir_p(path) }

    fake_autoloader = Struct.new(:dirs, :pushed, :skipped, :setup_called) do
      def push_dir(path) = pushed << path
      def do_not_eager_load(path) = skipped << path
      def setup = self.setup_called = true
    end.new([ configured_path ], [], [], false)
    fake_autoloaders = Struct.new(:once).new(fake_autoloader)
    original_autoloaders = Rails.method(:autoloaders)
    original_once_paths = ActiveSupport::Dependencies.autoload_once_paths
    original_eager_load = ActiveSupport::Dependencies.method(:eager_load?)
    Rails.define_singleton_method(:autoloaders) { fake_autoloaders }
    ActiveSupport::Dependencies.autoload_once_paths = [ eager_path, lazy_path, configured_path, missing_path, lazy_path ]
    ActiveSupport::Dependencies.define_singleton_method(:eager_load?) { |path| path.to_s == eager_path }

    run_bootstrap_initializer(app, :setup_once_autoloader)

    assert_equal [ eager_path, lazy_path ], fake_autoloader.pushed
    assert_equal [ lazy_path ], fake_autoloader.skipped
    assert fake_autoloader.setup_called
  ensure
    Rails.define_singleton_method(:autoloaders) { |*args, **kwargs, &block| original_autoloaders.call(*args, **kwargs, &block) } if original_autoloaders
    ActiveSupport::Dependencies.autoload_once_paths = original_once_paths unless original_once_paths&.frozen?
    ActiveSupport::Dependencies.define_singleton_method(:eager_load?) { |*args, **kwargs, &block| original_eager_load.call(*args, **kwargs, &block) } if original_eager_load
  end

  test "bootstrap hook runs before initialize load hooks with the application" do
    app = new_application
    seen = []
    ActiveSupport.on_load(:before_initialize) { |application| seen << application }

    run_bootstrap_initializer(app, :bootstrap_hook)

    assert_equal [ app ], seen
  end

  private
    def new_application
      root = Dir.mktmpdir("rails-bootstrap-public-contract")
      app = Class.new(Rails::Application).create
      app.config.root = Pathname.new(root)
      app.config.paths["log"] = File.join(root, "log", "test.log")
      app.config.cache_store = [ :memory_store ]
      FileUtils.mkdir_p(File.dirname(app.config.paths["log"].first))
      app
    end

    def run_bootstrap_initializer(app, name)
      app.initializers.find { |initializer| initializer.name == name }.run(app)
    end
end
