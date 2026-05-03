# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/unused_routes/unused_routes_command"

class UnusedRoutesPublicContractTest < ActiveSupport::TestCase
  setup do
    @application = Object.new
  end

  teardown do
    remove_constant(:PostsController)
  end

  test "route info treats missing controller and missing action without template as unused" do
    missing_controller_route = fake_route(controller: "missing", action: "show")
    assert Rails::Command::UnusedRoutesCommand::RouteInfo.new(missing_controller_route).unused?

    controller = Class.new
    controller.define_singleton_method(:view_paths) { [] }
    Object.const_set(:PostsController, controller)
    missing_action_route = fake_route(controller: "posts", action: "missing")
    assert Rails::Command::UnusedRoutesCommand::RouteInfo.new(missing_action_route).unused?
  end

  test "route info treats existing action or template as used" do
    controller = Class.new do
      def index; end
    end
    controller.define_singleton_method(:view_paths) { [] }
    Object.const_set(:PostsController, controller)

    assert_not Rails::Command::UnusedRoutesCommand::RouteInfo.new(fake_route(controller: "posts", action: "index")).unused?

    root = Dir.mktmpdir
    FileUtils.mkdir_p(File.join(root, "posts"))
    File.write(File.join(root, "posts", "show.html.erb"), "")
    controller.define_singleton_method(:view_paths) { [ Struct.new(:path).new(root) ] }

    assert_not Rails::Command::UnusedRoutesCommand::RouteInfo.new(fake_route(controller: "posts", action: "show")).unused?
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "perform prints formatted unused routes and exits nonzero when any remain" do
    unused = fake_route(controller: "missing", action: "show")
    used = fake_route(controller: nil, action: nil)
    routes = Struct.new(:routes).new([unused, used])
    @application.define_singleton_method(:routes) { routes }
    inspector = fake_inspector("unused routes")
    inspector_class = Class.new do
      define_singleton_method(:new) do |routes|
        inspector.routes = routes
        inspector
      end
    end
    command = Rails::Command::UnusedRoutesCommand.new([], ["--controller=MissingController", "--grep=missing"])
    booted = false
    command.define_singleton_method(:boot_application!) { booted = true }

    with_rails_application(@application) do
      replace_action_dispatch_inspector(inspector_class) do
        output = capture(:stdout) do
          error = assert_raises(SystemExit) { command.perform }
          assert_equal 1, error.status
        end
        assert_equal "unused routes\n", output
      end
    end

    assert booted
    assert_equal 1, inspector.routes.length
    assert_instance_of ActionDispatch::Routing::ConsoleFormatter::Unused, inspector.formatter
    assert_equal({ controller: "MissingController", grep: "missing" }, inspector.filter)
  end

  test "perform does not exit when no unused routes exist" do
    used = fake_route(controller: nil, action: nil)
    @application.define_singleton_method(:routes) { Struct.new(:routes).new([used]) }
    inspector = fake_inspector("no unused routes")
    inspector_class = Class.new do
      define_singleton_method(:new) do |routes|
        inspector.routes = routes
        inspector
      end
    end
    command = Rails::Command::UnusedRoutesCommand.new([], [])
    command.define_singleton_method(:boot_application!) { }

    with_rails_application(@application) do
      replace_action_dispatch_inspector(inspector_class) do
        assert_equal "no unused routes\n", capture(:stdout) { command.perform }
      end
    end

    assert_empty inspector.routes
    assert_equal({}, inspector.filter)
  end

  private
    def fake_route(controller:, action:)
      Struct.new(:requirements).new({ controller: controller, action: action })
    end

    def fake_inspector(result)
      Struct.new(:result, :routes, :formatter, :filter) do
        def format(formatter, filter)
          self.formatter = formatter
          self.filter = filter
          result
        end
      end.new(result)
    end

    def with_rails_application(app)
      singleton = class << Rails; self; end
      original = Rails.method(:application)
      singleton.define_method(:application) { app }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def replace_action_dispatch_inspector(inspector_class)
      require "action_dispatch/routing/inspector"
      original = ActionDispatch::Routing.const_get(:RoutesInspector)
      ActionDispatch::Routing.send(:remove_const, :RoutesInspector)
      ActionDispatch::Routing.const_set(:RoutesInspector, inspector_class)
      yield
    ensure
      ActionDispatch::Routing.send(:remove_const, :RoutesInspector)
      ActionDispatch::Routing.const_set(:RoutesInspector, original)
    end

    def remove_constant(name)
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
end
