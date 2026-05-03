# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/console/console_command"

class ConsolePublicContractTest < ActiveSupport::TestCase
  setup do
    @previous_env = Rails.env
  end

  teardown do
    Rails.env = @previous_env
  end

  test "class start builds a console and starts it" do
    app = fake_app(console: fake_console)

    Rails::Console.start(app, environment: "test")

    assert app.console.started
    assert_equal "test", Rails.env
  end

  test "initialize loads console sets sandbox and uses configured console" do
    configured_console = fake_console
    app = fake_app(console: configured_console, sandbox_by_default: false)
    console = Rails::Console.new(app, sandbox: true, environment: "production")

    assert_same app, console.app
    assert_equal({ sandbox: true, environment: "production" }, console.options)
    assert_same configured_console, console.console
    assert app.sandbox
    assert app.console_loaded
    assert console.sandbox?
    assert_equal "production", console.environment
  end

  test "sandbox falls back to application default outside local environments" do
    app = fake_app(sandbox_by_default: true)

    with_rails_env("production") do
      assert Rails::Console.new(app, sandbox: nil).sandbox?
    end

    with_rails_env("development") do
      assert_not Rails::Console.new(fake_app(sandbox_by_default: true), sandbox: nil).sandbox?
    end

    assert_equal false, Rails::Console.new(fake_app, sandbox: false).sandbox?
  end

  test "disabled sandbox exits with message" do
    app = fake_app(disable_sandbox: true)

    output = capture(:stdout) do
      exit = assert_raises(SystemExit) { Rails::Console.new(app, sandbox: true) }
      assert_equal 1, exit.status
    end

    assert_includes output, "sandbox mode is disabled"
  end

  test "start reports sandbox and normal modes before starting backend console" do
    app = fake_app(console: fake_console)
    normal = Rails::Console.new(app, environment: "test", sandbox: false)

    normal_output = capture(:stdout) { normal.start }
    assert_includes normal_output, "Loading test environment (Rails"
    assert_includes normal_output, "Type 'help' for help."
    assert normal.console.started

    sandbox_app = fake_app(console: fake_console)
    sandbox = Rails::Console.new(sandbox_app, environment: "production", sandbox: true)
    sandbox_output = capture(:stdout) { sandbox.start }

    assert_includes sandbox_output, "Loading production environment in sandbox (Rails"
    assert_includes sandbox_output, "rolled back on exit"
    assert sandbox.console.started
  end

  test "set environment updates rails env" do
    console = Rails::Console.new(fake_app, environment: "custom", sandbox: false)

    console.set_environment!

    assert_equal "custom", Rails.env
  end

  test "default console falls back to irb console and start can omit environment" do
    app = fake_app(console: nil)
    console = Rails::Console.new(app, sandbox: false)

    assert_equal "IRB", console.console.name

    console = Rails::Console.new(fake_app(console: fake_console), sandbox: false)
    output = capture(:stdout) { console.start }
    assert_includes output, "Loading #{Rails.env} environment (Rails"
  end

  private
    FakeConsole = Struct.new(:started) do
      def start
        self.started = true
      end
    end

    FakeConfig = Struct.new(:console, :disable_sandbox, :sandbox_by_default)

    def fake_console
      FakeConsole.new(false)
    end

    def fake_app(console: fake_console, disable_sandbox: false, sandbox_by_default: false)
      config = FakeConfig.new(console, disable_sandbox, sandbox_by_default)
      Object.new.tap do |app|
        app.define_singleton_method(:config) { config }
        app.define_singleton_method(:console) { config.console }
        app.define_singleton_method(:sandbox) { @sandbox }
        app.define_singleton_method(:sandbox=) { |value| @sandbox = value }
        app.define_singleton_method(:console_loaded) { @console_loaded }
        app.define_singleton_method(:load_console) { @console_loaded = true }
      end
    end

    def with_rails_env(env)
      old = Rails.env
      Rails.env = env
      yield
    ensure
      Rails.env = old
    end
end
