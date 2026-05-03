# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/routes/routes_command"

class RoutesPublicContractTest < ActiveSupport::TestCase
  setup do
    @application = Object.new
    routes = Struct.new(:routes).new([:route_one])
    @application.define_singleton_method(:routes) { routes }
  end

  test "invoke command delegates unused option to unused routes command" do
    invoked = []
    command = Rails::Command::RoutesCommand.new([], ["--unused"])

    with_singleton_method(Rails::Command, :invoke, ->(name, argv) { invoked << [name, argv.dup] }) do
      original_argv = ARGV.dup
      ARGV.replace(["--unused"])
      command.invoke_command(nil)
    ensure
      ARGV.replace(original_argv)
    end

    assert_equal [["unused_routes", ["--unused"]]], invoked
  end

  test "invoke command falls back to thor invocation without unused option" do
    command = Rails::Command::RoutesCommand.new([], [])

    output = capture(:stdout) do
      command.invoke_command(Rails::Command::RoutesCommand.commands["routes"])
    end

    assert_includes output, "routes"
  end

  test "perform boots app and prints formatted routes with filters" do
    command = Rails::Command::RoutesCommand.new([], ["--controller=PostsController", "--grep=posts"])
    booted = false
    command.define_singleton_method(:boot_application!) { booted = true }
    inspector = fake_inspector("formatted routes")
    inspector_class = Class.new do
      define_singleton_method(:new) do |routes|
        inspector.routes = routes
        inspector
      end
    end

    with_rails_application(@application) do
      replace_action_dispatch_inspector(inspector_class) do
        output = capture(:stdout) { command.perform }
        assert_equal "formatted routes\n", output
      end
    end

    assert booted
    assert_equal [:route_one], inspector.routes
    assert_instance_of ActionDispatch::Routing::ConsoleFormatter::Sheet, inspector.formatter
    assert_equal({ controller: "PostsController", grep: "posts" }, inspector.filter)
  end

  test "expanded option uses expanded formatter and routes filter omits absent filters" do
    command = Rails::Command::RoutesCommand.new([], ["--expanded"])
    inspector = fake_inspector("expanded routes")
    inspector_class = Class.new do
      define_singleton_method(:new) { |_routes| inspector }
    end

    with_rails_application(@application) do
      replace_action_dispatch_inspector(inspector_class) do
        capture(:stdout) { command.perform }
      end
    end

    assert_instance_of ActionDispatch::Routing::ConsoleFormatter::Expanded, inspector.formatter
    assert_equal({}, inspector.filter)
  end

  private
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

    def with_singleton_method(object, name, replacement)
      singleton = class << object; self; end
      original = object.method(name) if object.respond_to?(name)
      had_own_method = singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.send(:remove_method, name) if had_own_method
      singleton.define_method(name, replacement)
      yield
    ensure
      singleton.send(:remove_method, name) if singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if original && had_own_method
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
end
