# frozen_string_literal: true

require "abstract_unit"
require "rails/application/finisher"

class FinisherPublicContractTest < ActiveSupport::TestCase
  test "monitor hook enters and exits monitor around executor state" do
    monitor = MonitorSpy.new
    hook = Rails::Application::Finisher::MonitorHook.new(monitor)

    hook.run
    hook.complete(:state)

    assert_equal [ :enter, :exit ], monitor.calls
  end

  test "interlock hook delegates to dependencies interlock" do
    interlock = InterlockSpy.new
    original_interlock = ActiveSupport::Dependencies.interlock
    ActiveSupport::Dependencies.singleton_class.define_method(:interlock) { interlock }

    Rails::Application::Finisher::InterlockHook.run
    Rails::Application::Finisher::InterlockHook.complete(:state)

    assert_equal [ :start_running, :done_running ], interlock.calls
  ensure
    ActiveSupport::Dependencies.singleton_class.define_method(:interlock) { original_interlock }
  end

  test "finisher initializers wire templates sessions middleware helpers prepare and eager loading" do
    app = FinisherApp.new
    app.config.eager_load = true
    app.config.eager_load_namespaces = [ EagerNamespace.new ]
    app.config.reloading_enabled = true

    with_load_hook_spies(app) do
      run_initializer(:add_generator_templates, app)
      run_initializer(:setup_default_session_store, app, app)
      run_initializer(:build_middleware_stack, app)
      run_initializer(:define_main_app_helper, app, app)
      run_initializer(:add_to_prepare_blocks, app, app)
      run_initializer(:run_prepare_callbacks, app, app)
      run_initializer(:eager_load!, app, app)
      run_initializer(:finisher_hook, app)
      app.reloader.after_class_unload_blocks.first.call
    end

    assert app.generator_templates_added
    assert_equal :cookie_store, app.config.session_store_name
    assert_equal({ key: "_contract_session" }, app.config.session_store_options)
    assert app.middleware_stack_built
    assert_equal [ :main_app ], app.routes.mounted_helpers
    assert_equal 1, app.reloader.prepare_blocks.length
    assert app.reloader.prepared
    assert app.zeitwerk_eager_loaded
    assert app.rails_eager_loaded
    assert app.config.eager_load_namespaces.first.eager_loaded
    assert_equal [ :before_eager_load, :after_initialize ], app.load_hooks
    assert_equal 1, app.reloader.after_class_unload_blocks.length
    assert app.main_autoloader_eager_loaded
  end

  test "main autoloader setup adds existing paths respects configured paths and tracks reloadable classes" do
    app = FinisherApp.new
    app.config.reloading_enabled = true
    dir = Dir.mktmpdir("rails-finisher-autoload")
    missing = File.join(dir, "missing")
    autoloader = AutoloaderSpy.new(dirs: [ dir ])

    with_main_autoloader(autoloader, autoload_paths: [ dir, missing ], eager_load_paths: [ missing ]) do
      run_initializer(:setup_main_autoloader, app)
    end

    assert_empty autoloader.pushed_dirs
    assert autoloader.reloading_enabled
    assert autoloader.setup_called

    tracked = Class.new
    tracked.singleton_class.include ActiveSupport::DescendantsTracker
    autoloader.on_load_block.call("Tracked", tracked, "tracked.rb")
    autoloader.on_load_block.call("Plain", Object.new, "plain.rb")
    assert_includes ActiveSupport::Dependencies._autoloaded_tracked_classes, tracked

    fresh = Dir.mktmpdir("rails-finisher-autoload-fresh")
    plain_autoloader = AutoloaderSpy.new(dirs: [])
    app.config.reloading_enabled = false
    with_main_autoloader(plain_autoloader, autoload_paths: [ fresh ], eager_load_paths: []) do
      run_initializer(:setup_main_autoloader, app)
    end
    assert_equal [ fresh ], plain_autoloader.pushed_dirs
    assert_equal [ fresh ], plain_autoloader.do_not_eager_load_paths

    eager_path = Dir.mktmpdir("rails-finisher-autoload-eager")
    eager_autoloader = AutoloaderSpy.new(dirs: [])
    with_main_autoloader(eager_autoloader, autoload_paths: [ eager_path ], eager_load_paths: [ eager_path ]) do
      run_initializer(:setup_main_autoloader, app)
    end
    assert_equal [ eager_path ], eager_autoloader.pushed_dirs
    assert_empty eager_autoloader.do_not_eager_load_paths
  ensure
    FileUtils.rm_rf(dir) if dir
    FileUtils.rm_rf(fresh) if fresh
    FileUtils.rm_rf(eager_path) if eager_path
    ActiveSupport::Dependencies._autoloaded_tracked_classes.delete(tracked) if tracked
  end

  test "eager load initializer skips disabled eager load and after unload hook when reload is disabled" do
    disabled = FinisherApp.new
    disabled.config.eager_load = false
    with_load_hook_spies(disabled) do
      run_initializer(:eager_load!, disabled, disabled)
    end
    assert_not disabled.zeitwerk_eager_loaded

    no_reload = FinisherApp.new
    no_reload.config.eager_load = true
    no_reload.config.reloading_enabled = false
    with_load_hook_spies(no_reload) do
      run_initializer(:eager_load!, no_reload, no_reload)
    end
    assert no_reload.zeitwerk_eager_loaded
    assert_empty no_reload.reloader.after_class_unload_blocks
  end

  test "setup default session store preserves configured store and anonymous app key" do
    app = FinisherApp.new
    app.config.session_store :cache_store, key: "custom"

    run_initializer(:setup_default_session_store, app, app)

    assert_equal :cache_store, app.config.session_store_name
    assert_equal({ key: "custom" }, app.config.session_store_options)

    anonymous = FinisherApp.new(class_name: nil)
    run_initializer(:setup_default_session_store, anonymous, anonymous)
    assert_equal({ key: "__session" }, anonymous.config.session_store_options)
  end

  test "executor concurrency initializer registers monitor interlock or nothing" do
    app = FinisherApp.new
    app.config.allow_concurrency = false
    run_initializer(:configure_executor_for_concurrency, app, app)
    assert_instance_of Rails::Application::Finisher::MonitorHook, app.executor.hooks.first.first

    unsafe = FinisherApp.new
    unsafe.config.allow_concurrency = :unsafe
    run_initializer(:configure_executor_for_concurrency, unsafe, unsafe)
    assert_empty unsafe.executor.hooks

    safe = FinisherApp.new
    safe.config.allow_concurrency = true
    safe.config.reloading_enabled = true
    run_initializer(:configure_executor_for_concurrency, safe, safe)
    assert_equal Rails::Application::Finisher::InterlockHook, safe.executor.hooks.first.first

    no_reloading = FinisherApp.new
    no_reloading.config.allow_concurrency = true
    no_reloading.config.reloading_enabled = false
    run_initializer(:configure_executor_for_concurrency, no_reloading, no_reloading)
    assert_empty no_reloading.executor.hooks
  end

  test "internal routes are development only and route reloader hook loads eager or non lazy routes" do
    original_env = Rails.env
    Rails.env = "development"
    app = FinisherApp.new

    run_initializer(:add_internal_routes, app, app)

    assert_includes app.routes.prepended_paths, "/rails/info"
    assert app.routes_reloader.run_after_load_paths
    app.routes_reloader.run_after_load_paths.call
    assert_includes app.routes.appended_paths, "/"

    run_initializer(:set_routes_reloader_hook, app, app)
    assert_includes app.reloaders, app.routes_reloader
    assert app.routes_reloader.executed_unless_loaded
    assert_equal app.config.eager_load, app.routes_reloader.eager_load
    with_route_load_hook_spy(app) do
      app.reloader.run_blocks.first.call
    end
    assert app.unload_lock_required
    assert app.routes_reloader.executed
    assert_includes app.load_hooks, :after_routes_loaded

    lazy = FinisherApp.new
    lazy.routes = Rails::Engine::LazyRouteSet.new
    lazy.config.eager_load = false
    run_initializer(:set_routes_reloader_hook, lazy, lazy)
    assert_not lazy.routes_reloader.executed_unless_loaded

    Rails.env = "production"
    production = FinisherApp.new
    run_initializer(:add_internal_routes, production, production)
    assert_empty production.routes.prepended_paths
  ensure
    Rails.env = original_env
  end

  test "clear dependencies hook configures reloader checks callbacks and disabled clearing" do
    app = FinisherApp.new
    app.config.reloading_enabled = true
    app.config.reload_classes_only_on_change = true
    watcher = WatcherSpy
    app.config.file_watcher = watcher

    with_dependency_clear_spies do
      run_initializer(:set_clear_dependencies_hook, app, app)

      assert_equal [ :watchable ], watcher.instances.first.args
      assert_includes app.reloaders, watcher.instances.first
      assert_equal true, app.reloader.check.call
      assert_equal 1, app.reloader.run_blocks.length
      app.reloader.run_blocks.first.call
      assert watcher.instances.first.executed
      assert app.class_unloaded

      always = FinisherApp.new
      always.config.reloading_enabled = true
      always.config.reload_classes_only_on_change = false
      run_initializer(:set_clear_dependencies_hook, always, always)
      assert_equal true, always.reloader.check.call
      assert_equal 1, always.reloader.complete_blocks.length
      always.reloader.complete_blocks.first.call
      assert always.class_unloaded

      disabled = FinisherApp.new
      disabled.config.reloading_enabled = false
      run_initializer(:set_clear_dependencies_hook, disabled, disabled)
      assert_equal false, disabled.reloader.check.call
    end
  end

  test "yjit initializer enables yjit only when configured" do
    app = FinisherApp.new
    yjit = YjitSpy.new

    with_yjit(yjit) do
      app.config.yjit = { stats: true }
      run_initializer(:enable_yjit, app)
      app.config.yjit = true
      run_initializer(:enable_yjit, app)
      app.config.yjit = false
      run_initializer(:enable_yjit, app)
    end

    assert_equal [ { stats: true }, {} ], yjit.calls
  end

  private
    def run_initializer(name, context, *args)
      initializer = Rails::Application::Finisher.initializers.find { |candidate| candidate.name == name }
      initializer.bind(context).run(*args)
    end

    def with_load_hook_spies(app)
      loader_singleton = class << Zeitwerk::Loader; self; end
      original_zeitwerk_eager_load_all = Zeitwerk::Loader.method(:eager_load_all)
      rails_singleton = class << Rails; self; end
      original_eager_load = Rails.method(:eager_load!)
      original_autoloaders = Rails.method(:autoloaders)
      original_run_load_hooks = ActiveSupport.method(:run_load_hooks)
      main_loader = Object.new
      main_loader.define_singleton_method(:eager_load) { app.main_autoloader_eager_loaded = true }
      autoloaders = Struct.new(:main).new(main_loader)
      loader_singleton.define_method(:eager_load_all) { app.zeitwerk_eager_loaded = true }
      rails_singleton.define_method(:eager_load!) { app.rails_eager_loaded = true }
      rails_singleton.define_method(:autoloaders) { autoloaders }
      ActiveSupport.singleton_class.define_method(:run_load_hooks) { |name, _target| app.load_hooks << name }
      yield
    ensure
      loader_singleton.define_method(:eager_load_all) { |*a, **k, &b| original_zeitwerk_eager_load_all.call(*a, **k, &b) }
      rails_singleton.define_method(:eager_load!) { |*a, **k, &b| original_eager_load.call(*a, **k, &b) }
      rails_singleton.define_method(:autoloaders) { |*a, **k, &b| original_autoloaders.call(*a, **k, &b) }
      ActiveSupport.singleton_class.define_method(:run_load_hooks) { |*a, **k, &b| original_run_load_hooks.call(*a, **k, &b) }
    end

    def with_dependency_clear_spies
      dependencies_singleton = class << ActiveSupport::Dependencies; self; end
      descendants_singleton = class << ActiveSupport::DescendantsTracker; self; end
      original_dependencies_clear = ActiveSupport::Dependencies.method(:clear)
      original_descendants_clear = ActiveSupport::DescendantsTracker.method(:clear)
      original_disable_clear = ActiveSupport::DescendantsTracker.method(:disable_clear!)
      dependencies_singleton.define_method(:clear) { true }
      descendants_singleton.define_method(:clear) { |_| true }
      descendants_singleton.define_method(:disable_clear!) { true }
      yield
    ensure
      dependencies_singleton.define_method(:clear) { |*a, **k, &b| original_dependencies_clear.call(*a, **k, &b) }
      descendants_singleton.define_method(:clear) { |*a, **k, &b| original_descendants_clear.call(*a, **k, &b) }
      descendants_singleton.define_method(:disable_clear!) { |*a, **k, &b| original_disable_clear.call(*a, **k, &b) }
    end

    def with_main_autoloader(autoloader, autoload_paths:, eager_load_paths:)
      autoloaders = Struct.new(:main).new(autoloader)
      rails_singleton = class << Rails; self; end
      original_autoloaders = Rails.method(:autoloaders)
      original_autoload_paths = ActiveSupport::Dependencies.autoload_paths.dup
      original_eager_load_paths = ActiveSupport::Dependencies._eager_load_paths.dup
      Rails.singleton_class.define_method(:autoloaders) { autoloaders }
      ActiveSupport::Dependencies.autoload_paths = autoload_paths
      ActiveSupport::Dependencies._eager_load_paths = eager_load_paths
      yield
    ensure
      rails_singleton.define_method(:autoloaders) { |*a, **k, &b| original_autoloaders.call(*a, **k, &b) }
      ActiveSupport::Dependencies.autoload_paths = original_autoload_paths
      ActiveSupport::Dependencies._eager_load_paths = original_eager_load_paths
    end

    def with_route_load_hook_spy(app)
      original_run_load_hooks = ActiveSupport.method(:run_load_hooks)
      ActiveSupport.singleton_class.define_method(:run_load_hooks) { |name, _target| app.load_hooks << name }
      yield
    ensure
      ActiveSupport.singleton_class.define_method(:run_load_hooks) { |*a, **k, &b| original_run_load_hooks.call(*a, **k, &b) }
    end

    def with_yjit(yjit)
      ruby_vm = Class.new
      ruby_vm.const_set(:YJIT, yjit)
      original = Object.const_get(:RubyVM)
      Object.send(:remove_const, :RubyVM)
      Object.const_set(:RubyVM, ruby_vm)
      yield
    ensure
      Object.send(:remove_const, :RubyVM)
      Object.const_set(:RubyVM, original)
    end

    class MonitorSpy
      attr_reader :calls
      def initialize = @calls = []
      def enter = @calls << :enter
      def exit = @calls << :exit
    end

    class InterlockSpy
      attr_reader :calls
      def initialize = @calls = []
      def start_running = @calls << :start_running
      def done_running = @calls << :done_running
    end

    class AutoloaderSpy
      attr_reader :dirs, :pushed_dirs, :do_not_eager_load_paths, :on_load_block
      attr_accessor :reloading_enabled, :setup_called

      def initialize(dirs:)
        @dirs = dirs
        @pushed_dirs = []
        @do_not_eager_load_paths = []
      end

      def push_dir(path) = @pushed_dirs << path
      def do_not_eager_load(path) = @do_not_eager_load_paths << path
      def enable_reloading = @reloading_enabled = true
      def on_load(&block) = @on_load_block = block
      def setup = @setup_called = true
      def eager_load = @eager_loaded = true
      def eager_loaded? = @eager_loaded
    end

    class YjitSpy
      attr_reader :calls
      def initialize = @calls = []
      def enable(**options) = @calls << options
    end

    class EagerNamespace
      attr_reader :eager_loaded
      def eager_load! = @eager_loaded = true
    end

    class ExecutorSpy
      attr_reader :hooks
      def initialize = @hooks = []
      def register_hook(hook, outer:) = @hooks << [ hook, outer ]
    end

    class ReloaderSpy
      attr_accessor :check
      attr_reader :prepare_blocks, :after_class_unload_blocks, :run_blocks, :complete_blocks
      attr_accessor :prepared
      def initialize
        @prepare_blocks = []
        @after_class_unload_blocks = []
        @run_blocks = []
        @complete_blocks = []
      end
      def to_prepare(&block) = @prepare_blocks << block
      def prepare! = @prepared = true
      def after_class_unload(&block) = @after_class_unload_blocks << block
      def to_run(prepend: false, &block) = prepend ? @run_blocks.unshift(block) : @run_blocks << block
      def to_complete(&block) = @complete_blocks << block
    end

    class RoutesSpy
      attr_reader :mounted_helpers, :prepended_paths, :appended_paths
      def initialize
        @mounted_helpers = []
        @prepended_paths = []
        @appended_paths = []
      end
      def define_mounted_helper(name) = @mounted_helpers << name
      def prepend(&block) = instance_eval(&block)
      def append(&block) = instance_eval(&block)
      def get(path = nil, *args, **kwargs)
        path = path.keys.first if path.is_a?(Hash)
        path ||= kwargs.keys.first
        (@appending ? @appended_paths : @prepended_paths) << path
      end
      def append(&block)
        @appending = true
        instance_eval(&block)
      ensure
        @appending = false
      end
    end

    class RoutesReloaderSpy
      attr_accessor :eager_load, :run_after_load_paths
      attr_reader :executed, :executed_unless_loaded
      def execute
        @executed = true
      end
      def execute_unless_loaded
        @executed_unless_loaded = true
      end
    end

    class WatcherSpy
      class << self
        attr_accessor :instances
      end
      self.instances = []
      attr_reader :args
      attr_accessor :executed
      def initialize(*args, &block)
        @args = args
        @block = block
        self.class.instances << self
      end
      def execute
        @executed = true
        @block.call
      end
      def updated? = true
    end

    class FinisherConfig
      attr_accessor :eager_load, :eager_load_namespaces, :allow_concurrency,
        :reload_classes_only_on_change, :file_watcher, :yjit
      attr_writer :reloading_enabled
      attr_reader :to_prepare_blocks, :session_store_name, :session_store_options

      def initialize
        @eager_load = false
        @eager_load_namespaces = []
        @allow_concurrency = true
        @reloading_enabled = false
        @reload_classes_only_on_change = true
        @file_watcher = WatcherSpy
        @to_prepare_blocks = [ -> {} ]
        @yjit = false
      end

      def session_store?(*) = @session_store_name
      def session_store(name, **options)
        @session_store_name = name
        @session_store_options = options
      end
      def reloading_enabled? = @reloading_enabled
    end

    class FinisherApp
      attr_reader :config, :reloader, :executor, :routes_reloader, :reloaders, :load_hooks
      attr_accessor :routes
      attr_accessor :generator_templates_added, :middleware_stack_built, :zeitwerk_eager_loaded,
        :rails_eager_loaded, :class_unloaded, :unload_lock_required, :main_autoloader_eager_loaded

      def initialize(class_name: "Contract::Application")
        @config = FinisherConfig.new
        @routes = RoutesSpy.new
        @reloader = ReloaderSpy.new
        @executor = ExecutorSpy.new
        @routes_reloader = RoutesReloaderSpy.new
        @reloaders = []
        @load_hooks = []
        @class_name = class_name
      end

      def class = ClassName.new(@class_name)
      def railtie_name = "contract_application"
      def ensure_generator_templates_added = @generator_templates_added = true
      def build_middleware_stack = @middleware_stack_built = true
      def watchable_args = [ :watchable ]
      def require_unload_lock! = @unload_lock_required = true
      def class_unload!
        @class_unloaded = true
        yield if block_given?
      end
    end

    ClassName = Struct.new(:name)
end
