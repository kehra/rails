# frozen_string_literal: true

require "abstract_unit"
require "rails/app_loader"
require "rails/command"

class RailsCliTest < ActiveSupport::TestCase
  CLI_PATH = File.expand_path("../lib/rails/cli.rb", __dir__)

  test "help arguments invoke gem help and shift the help token" do
    skip "mode-filtered coverage run" if mode && mode != "help"

    invoked = invoke_cli_with("help", "server")

    assert_equal [ [ :gem_help, [ "server" ] ] ], invoked
  end

  test "plugin argument invokes plugin command and shifts the plugin token" do
    skip "mode-filtered coverage run" if mode && mode != "plugin"

    invoked = invoke_cli_with("plugin", "new", "my_plugin")

    assert_equal [ [ :plugin, [ "new", "my_plugin" ] ] ], invoked
  end

  test "other arguments invoke application command without shifting" do
    skip "mode-filtered coverage run" if mode && mode != "application"

    invoked = invoke_cli_with("new", "my_app")

    assert_equal [ [ :application, [ "new", "my_app" ] ] ], invoked
  end

  test "missing argument invokes gem help" do
    skip "mode-filtered coverage run" if mode && mode != "missing"

    invoked = invoke_cli_with

    assert_equal [ [ :gem_help, [] ] ], invoked
  end

  def mode
    ENV["RAILS_CLI_TEST_MODE"]
  end

  private
    def invoke_cli_with(*arguments)
      old_argv = ARGV.dup
      old_int_handler = Signal.trap("INT", "DEFAULT")
      invoked = []
      ARGV.replace(arguments)

      app_loader_singleton = class << Rails::AppLoader; self; end
      command_singleton = class << Rails::Command; self; end
      original_exec_app = Rails::AppLoader.method(:exec_app)
      original_invoke = Rails::Command.method(:invoke)

      app_loader_singleton.define_method(:exec_app) { false }
      command_singleton.define_method(:invoke) { |command, args| invoked << [ command, args.dup ] }

      load CLI_PATH

      invoked
    ensure
      app_loader_singleton&.define_method(:exec_app) { |*args, **kwargs, &block| original_exec_app.call(*args, **kwargs, &block) }
      command_singleton&.define_method(:invoke) { |*args, **kwargs, &block| original_invoke.call(*args, **kwargs, &block) }
      ARGV.replace(old_argv)
      Signal.trap("INT", old_int_handler)
    end
end
