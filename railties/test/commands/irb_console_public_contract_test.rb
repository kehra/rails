# frozen_string_literal: true

require "abstract_unit"
require "rails/commands/console/irb_console"

class IRBConsolePublicContractTest < ActiveSupport::TestCase
  setup do
    @previous_env = Rails.env
    require "irb"
    @previous_irb_conf = IRB.conf.dup
    @previous_autocomplete = ENV["IRB_USE_AUTOCOMPLETE"]
  end

  teardown do
    Rails.env = @previous_env
    IRB.conf.clear
    IRB.conf.update(@previous_irb_conf)
    if @previous_autocomplete.nil?
      ENV.delete("IRB_USE_AUTOCOMPLETE")
    else
      ENV["IRB_USE_AUTOCOMPLETE"] = @previous_autocomplete
    end
    remove_constant(:ApplicationController)
    restore_constant(:ActionDispatch)
  end

  test "controller helpers delegate to application controller" do
    helpers = Object.new
    controller = Class.new
    controller.define_singleton_method(:helpers) { helpers }
    Object.const_set(:ApplicationController, controller)

    assert_same helpers, Rails::Console::ControllerHelper.send(:new).execute
    controller_helper = Rails::Console::ControllerInstance.send(:new)
    first = controller_helper.execute
    assert_instance_of controller, first
    assert_same first, controller_helper.execute
  end

  test "session helpers create and memoize integration sessions" do
    app = fake_application
    session_class = Class.new do
      attr_reader :app, :extensions
      def initialize(app)
        @app = app
        @extensions = []
      end
      def extend(mod)
        @extensions << mod
        self
      end
    end
    action_dispatch = Module.new
    integration = Module.new
    integration.const_set(:Session, session_class)
    action_dispatch.const_set(:Integration, integration)
    replace_constant(:ActionDispatch, action_dispatch)

    with_rails_application(app) do
      new_session = Rails::Console::NewSession.send(:new).execute
      assert_same app, new_session.app
      assert_equal [ :url_helpers, :mounted_helpers ], new_session.extensions
      assert_equal 1, app.reloads

      helper = Rails::Console::AppInstance.send(:new)
      first = helper.execute
      assert_same first, helper.execute
      assert_not_same first, helper.execute(true)
    end
  end

  test "reload helper resets active executor and reloads application" do
    app = fake_application
    app.executor.active = true

    with_rails_application(app) do
      output = capture(:stdout) { Rails::Console::ReloadHelper.send(:new).execute }
      assert_includes output, "Reloading..."
    end

    assert_equal [ { reset: true } ], app.executor.runs
    assert_equal 1, app.reloader.reloads

    inactive_app = fake_application
    with_rails_application(inactive_app) do
      capture(:stdout) { Rails::Console::ReloadHelper.send(:new).execute }
    end
    assert_empty inactive_app.executor.runs
    assert_equal 1, inactive_app.reloader.reloads
  end

  test "irb console exposes name colorized env and start configuration" do
    app = Object.new
    app.define_singleton_method(:name) { "DemoApp" }
    console = Rails::Console::IRBConsole.new(app)

    assert_equal "IRB", console.name
    Rails.env = "development"
    assert_includes console.colorized_env, "dev"
    Rails.env = "test"
    assert_includes console.colorized_env, "test"
    Rails.env = "production"
    assert_includes console.colorized_env, "prod"
    Rails.env = "staging"
    assert_includes console.colorized_env, "staging"

    Rails.env = "production"
    ENV.delete("IRB_USE_AUTOCOMPLETE")
    IRB.conf[:IRB_NAME] = "irb"
    IRB.conf[:PROMPT] = {}
    IRB.conf[:PROMPT_MODE] = :DEFAULT
    IRB.conf[:BACKTRACE_FILTER] = ->(backtrace) { backtrace + [ "user-filter" ] }
    runner = fake_irb_runner

    with_irb_stubs(runner) do
      console.start
    end

    assert_equal false, IRB.conf[:USE_AUTOCOMPLETE]
    assert_equal "DemoApp", IRB.conf[:IRB_NAME]
    assert_equal :RAILS_PROMPT, IRB.conf[:PROMPT_MODE]
    assert_includes IRB.conf[:PROMPT][:RAILS_PROMPT][:PROMPT_I], "prod"
    assert_equal [ "app/backtrace", "user-filter" ], IRB.conf[:BACKTRACE_FILTER].call([ "app/backtrace" ])
    assert_equal [ IRB.conf ], runner.runs

    IRB.conf[:BACKTRACE_FILTER] = nil
    IRB.conf[:PROMPT] = {}
    IRB.conf[:PROMPT_MODE] = :CUSTOM
    IRB.conf[:IRB_NAME] = "custom"
    ENV["IRB_USE_AUTOCOMPLETE"] = "1"
    Rails.env = "development"

    with_irb_stubs(fake_irb_runner) do
      console.start
    end

    assert_equal "custom", IRB.conf[:IRB_NAME]
    assert_equal :CUSTOM, IRB.conf[:PROMPT_MODE]
    assert_equal [ "app/backtrace" ], IRB.conf[:BACKTRACE_FILTER].call([ "app/backtrace" ])
  end

  private
    def fake_application
      routes = Object.new
      routes.define_singleton_method(:url_helpers) { :url_helpers }
      routes.define_singleton_method(:mounted_helpers) { :mounted_helpers }
      executor = Struct.new(:active, :runs) do
        def active? = active
        def run!(**options) = runs << options
      end.new(false, [])
      reloader = Struct.new(:reloads) do
        def reload! = self.reloads += 1
      end.new(0)
      Struct.new(:routes, :executor, :reloader, :reloads) do
        def reload_routes_unless_loaded = self.reloads += 1
      end.new(routes, executor, reloader, 0)
    end

    def fake_irb_runner
      Struct.new(:runs) do
        def run(config) = runs << config
      end.new([])
    end

    def with_rails_application(app)
      singleton = class << Rails; self; end
      original = Rails.method(:application) if Rails.respond_to?(:application)
      singleton.define_method(:application) { app }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if original
    end

    def with_irb_stubs(runner)
      irb_singleton = class << IRB; self; end
      original_setup = IRB.method(:setup)
      original_new = IRB::Irb.method(:new)
      irb_singleton.define_method(:setup) { |_value| }
      IRB::Irb.singleton_class.define_method(:new) { runner }
      yield
    ensure
      irb_singleton.send(:remove_method, :setup) if irb_singleton.method_defined?(:setup)
      irb_singleton.define_method(:setup) { |*args, **kwargs, &block| original_setup.call(*args, **kwargs, &block) }
      IRB::Irb.singleton_class.send(:remove_method, :new) if IRB::Irb.singleton_class.method_defined?(:new)
      IRB::Irb.singleton_class.define_method(:new) { |*args, **kwargs, &block| original_new.call(*args, **kwargs, &block) }
    end

    def replace_constant(name, value)
      @replaced_constants ||= {}
      @replaced_constants[name] = Object.const_get(name) if Object.const_defined?(name) && !@replaced_constants.key?(name)
      Object.send(:remove_const, name) if Object.const_defined?(name)
      Object.const_set(name, value)
    end

    def restore_constant(name)
      if defined?(@replaced_constants) && @replaced_constants.key?(name)
        Object.send(:remove_const, name) if Object.const_defined?(name)
        Object.const_set(name, @replaced_constants[name])
      else
        remove_constant(name)
      end
    end

    def remove_constant(name)
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
end
