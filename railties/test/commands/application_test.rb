# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/application/application_command"

class Rails::Command::ApplicationTest < ActiveSupport::TestCase
  test "rails new without path prints help" do
    output = run_application_command "new"

    # Doesn't include the default thor error message:
    assert_not output.start_with?("No value provided for required arguments")

    # Includes contents of ~/railties/lib/rails/generators/rails/app/USAGE:
    assert output.include?("The `rails new` command creates a new Rails application with a default
    directory structure and configuration at the path you specify.")
  end

  test "application command hides itself and delegates help and perform to app generator" do
    events = []
    command = Rails::Command::ApplicationCommand.new([], {}, {})

    assert Rails::Generators::AppGenerator.exit_on_failure?
    assert_includes Rails::Command.hidden_commands, Rails::Command::ApplicationCommand
    assert_equal "rails application", Rails::Command::ApplicationCommand.executable

    with_app_generator_spy(events) do
      command.perform("new", "demo")
      command.help
    end

    assert_equal 2, events.length
    assert_equal [ "demo" ], events.first
    assert_equal [ "--help" ], events.last
  end

  private
    def run_application_command(*args)
      capture(:stdout) { Rails::Command.invoke(:application, args) }
    end

    def with_app_generator_spy(events)
      singleton = class << Rails::Generators::AppGenerator; self; end
      original = Rails::Generators::AppGenerator.method(:start)
      singleton.define_method(:start) { |args| events << args }
      yield
    ensure
      singleton.send(:remove_method, :start) if singleton.method_defined?(:start)
      singleton.define_method(:start) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
