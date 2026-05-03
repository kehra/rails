# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/runner/runner_command"
require "active_support/core_ext/string/starts_ends_with"
require "stringio"

class RunnerPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_argv = ARGV.dup
    @original_stdin = $stdin
    @original_program_name = $0
    $runner_public_contract_value = nil
    $runner_public_contract_loaded = nil
  end

  teardown do
    ARGV.replace(@original_argv)
    $stdin = @original_stdin
    $0 = @original_program_name
    $runner_public_contract_value = nil
    $runner_public_contract_loaded = nil
  end

  test "help appends runner usage for runner command" do
    command = command_for
    with_singleton_method(Rails::Command::RunnerCommand, :class_usage, -> { "runner usage" }) do
      output = capture(:stdout) { command.help("runner") }
      assert_includes output, "runner usage"
    end
  end

  test "help omits runner usage for a non runner command" do
    command = command_for
    with_singleton_method(Rails::Command::RunnerCommand, :class_usage, -> { "runner usage" }) do
      output = capture(:stdout) { command.help("help") }
      assert_not_includes output, "runner usage"
    end
  end

  test "perform without code shows help and exits" do
    command = command_for
    helped = false
    command.define_singleton_method(:help) { helped = true }

    error = assert_raises(SystemExit) { command.perform }

    assert helped
    assert_equal 1, error.status
  end

  test "perform boots app loads runner replaces argv and evals code through executor" do
    app = fake_application
    command = command_for
    command.define_singleton_method(:boot_application!) { app.calls << :boot_application }

    with_rails_application(app) do
      command.perform('$runner_public_contract_value = [ARGV.dup, Rails.application.executor.wrapped]', "one", "two")
    end

    assert_equal [ :boot_application, :load_runner ], app.calls
    assert_equal [["one", "two"], true], $runner_public_contract_value
  end

  test "perform can skip executor" do
    app = fake_application
    command = command_for([], ["--skip-executor"])
    command.define_singleton_method(:boot_application!) { app.calls << :boot_application }

    with_rails_application(app) do
      command.perform('$runner_public_contract_value = Rails.application.executor.wrapped')
    end

    assert_equal false, $runner_public_contract_value
  end

  test "perform evals stdin when code argument is dash" do
    app = fake_application
    command = command_for
    command.define_singleton_method(:boot_application!) { app.calls << :boot_application }
    $stdin = StringIO.new('$runner_public_contract_value = :stdin')

    with_rails_application(app) do
      command.perform("-")
    end

    assert_equal :stdin, $runner_public_contract_value
  end

  test "perform loads existing file and updates program name" do
    app = fake_application
    command = command_for
    command.define_singleton_method(:boot_application!) { app.calls << :boot_application }
    file = Tempfile.new(["runner-public-contract", ".rb"])
    file.write('$runner_public_contract_loaded = $0')
    file.close

    with_rails_application(app) do
      command.perform(file.path)
    end

    assert_equal File.expand_path(file.path), $runner_public_contract_loaded
  ensure
    file&.unlink
  end

  test "missing ruby-looking file reports file path error" do
    app = fake_application
    command = command_for
    command.define_singleton_method(:boot_application!) { app.calls << :boot_application }

    output = with_rails_application(app) do
      capture(:stderr) do
        error = assert_raises(SystemExit) { command.perform("missing_runner_file.rb") }
        assert_equal 1, error.status
      end
    end

    assert_includes output, "The file missing_runner_file.rb could not be found"
    assert_includes output, "Run 'bin/rails runner -h' for help."
  end

  test "invalid code reports ruby command error" do
    app = fake_application
    command = command_for
    command.define_singleton_method(:boot_application!) { app.calls << :boot_application }

    output = with_rails_application(app) do
      capture(:stderr) do
        error = assert_raises(SystemExit) { command.perform("not valid ruby code") }
        assert_equal 1, error.status
      end
    end

    assert_includes output, "Please specify a valid ruby command"
    assert_includes output, "Run 'bin/rails runner -h' for help."
  end

  test "private helper detects ruby file paths" do
    command = command_for

    assert command.send(:looks_like_a_file_path?, "script.rb")
    assert_not command.send(:looks_like_a_file_path?, "puts 1")
  end

  private
    def command_for(args = [], options = [])
      Rails::Command::RunnerCommand.new(args, options)
    end

    def fake_application
      executor = Struct.new(:wrapped) do
        def wrap(**)
          self.wrapped = true
          yield
        ensure
          self.wrapped = false
        end
      end.new(false)
      Struct.new(:executor, :calls) do
        def load_runner = calls << :load_runner
      end.new(executor, [])
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
end
