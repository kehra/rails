# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/test/test_command"

class TestCommandPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_load_path = $LOAD_PATH.dup
    @original_rails_minitest_plugin = ENV["RAILS_MINITEST_PLUGIN"]
  end

  teardown do
    $LOAD_PATH.replace(@original_load_path)
    if @original_rails_minitest_plugin.nil?
      ENV.delete("RAILS_MINITEST_PLUGIN")
    else
      ENV["RAILS_MINITEST_PLUGIN"] = @original_rails_minitest_plugin
    end
  end

  test "executable delegates to reporter when no command name is provided" do
    with_singleton_method(Rails::TestUnitReporter, :executable, -> { "bin/rails test" }) do
      assert_equal "bin/rails test", Rails::Command::TestCommand.executable
    end

    assert_equal "bin/rails test:models", Rails::Command::TestCommand.executable(:models)
  end

  test "help appends usage for test command and minitest help" do
    command = command_for
    minitest_args = []
    with_singleton_method(Rails::Command::TestCommand, :class_usage, -> { "test usage" }) do
      with_singleton_method(Minitest, :run, ->(args) { minitest_args << args }) do
        output = capture(:stdout) { command.help("test") }
        assert_includes output, "test usage"
      end
    end

    assert_equal [%w(--help)], minitest_args
  end

  test "help omits usage for other command names but still prints minitest help" do
    command = command_for
    minitest_args = []
    with_singleton_method(Rails::Command::TestCommand, :class_usage, -> { "test usage" }) do
      with_singleton_method(Minitest, :run, ->(args) { minitest_args << args }) do
        output = capture(:stdout) { command.help("help") }
        assert_not_includes output, "test usage"
      end
    end

    assert_equal [%w(--help)], minitest_args
  end

  test "perform adds test load path parses options prepares when no exact test argument and runs" do
    calls = []
    command = command_for
    command.define_singleton_method(:run_prepare_task) { calls << :prepare }

    with_command_root(Pathname.new("/tmp/app")) do
      with_singleton_method(Rails::TestUnit::Runner, :parse_options, ->(args) { calls << [:parse, args] }) do
        with_singleton_method(Rails::TestUnit::Runner, :run, ->(args) { calls << [:run, args] }) do
          command.perform("--seed", "123")
        end
      end
    end

    assert_includes $LOAD_PATH, "/tmp/app/test"
    assert_equal [[:parse, ["--seed", "123"]], :prepare, [:run, ["--seed", "123"]]], calls
  end

  test "perform skips prepare for name and path arguments" do
    [["-n", "test_name"], ["--name=test_name"], ["test/models/user_test.rb"]].each do |args|
      calls = []
      command = command_for(args)
      command.define_singleton_method(:run_prepare_task) { calls << :prepare }

      with_command_root(Pathname.new("/tmp/app")) do
        with_singleton_method(Rails::TestUnit::Runner, :parse_options, ->(parsed_args) { calls << [:parse, parsed_args] }) do
          with_singleton_method(Rails::TestUnit::Runner, :run, ->(run_args) { calls << [:run, run_args] }) do
            command.perform(*args)
          end
        end
      end

      assert_not_includes calls, :prepare
      assert_equal [[:parse, args], [:run, args]], calls
    end
  end

  test "folder shortcuts and all delegate to perform with expanded paths" do
    command = command_for
    performed = []
    command.define_singleton_method(:perform) { |*args| performed << args }

    command.models("--seed", "1")
    command.all("--name=test_all")
    command.functionals
    command.units
    command.system
    command.generators

    assert_equal [
      ["test/models", "--seed", "1"],
      ["test/**/*_test.rb", "--name=test_all"],
      ["test/controllers", "test/mailers", "test/functional"],
      ["test/models", "test/helpers", "test/unit"],
      ["test/system"],
      ["test/lib/generators"],
    ], performed
  end

  test "run prepare task ignores missing test prepare task and re-raises other rake errors" do
    calls = []
    with_singleton_method(Rails::Command::RakeCommand, :perform, ->(task, args, config) { calls << [task, args, config] }) do
      command_for.send(:run_prepare_task)
    end
    assert_equal [["test:prepare", [], {}]], calls

    missing_prepare = Rails::Command::UnrecognizedCommandError.new("test:prepare")
    with_singleton_method(Rails::Command::RakeCommand, :perform, ->(*) { raise missing_prepare }) do
      assert_nothing_raised { command_for.send(:run_prepare_task) }
    end

    other_error = Rails::Command::UnrecognizedCommandError.new("assets:precompile")
    with_singleton_method(Rails::Command::RakeCommand, :perform, ->(*) { raise other_error }) do
      assert_same other_error, assert_raises(Rails::Command::UnrecognizedCommandError) { command_for.send(:run_prepare_task) }
    end
  end

  private
    def command_for(args = [], options = [])
      Rails::Command::TestCommand.new(args, options)
    end

    def with_command_root(root)
      with_singleton_method(Rails::Command, :root, -> { root }) { yield }
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
end
