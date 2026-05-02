# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "stringio"

class CommandPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_stdout = $stdout
    @original_env = ENV.to_hash
  end

  teardown do
    $stdout = @original_stdout
    ENV.replace(@original_env)
    remove_constant(:ENGINE_ROOT)
    remove_constant(:APP_PATH)
  end

  test "root prefers engine root and otherwise derives application root" do
    set_constant(:ENGINE_ROOT, "/tmp/engine-root")
    assert_equal Pathname.new("/tmp/engine-root"), Rails::Command.root

    remove_constant(:ENGINE_ROOT)
    set_constant(:APP_PATH, "/tmp/my_app/config/application")
    assert_equal Pathname.new("/tmp/my_app"), Rails::Command.root
  end

  test "invoke dispatches commands rake fallback and unrecognized command handling" do
    events = []
    command = FakeCommand.new(events, "demo" => true, "boom" => true)
    rake = FakeCommand.new(events, "fallback" => true)
    failing = FakeCommand.new(events, "fail" => true)
    failing.raise_unrecognized = "fail"

    with_command_lookup("demo" => command, "rake" => rake, "boom" => command, "namespace" => failing) do
      Rails::Command.invoke("demo", [ "one" ], option: :value)
      assert_equal [ [ command, "demo", [ "one" ], { option: :value }, [ "one" ] ] ], events
      assert_equal [ "test/command_public_contract_test.rb" ], ARGV

      Rails::Command.invoke("fallback", [ "--help" ], fallback: true)
      assert_includes events, [ rake, "fallback", [ "--describe", "fallback" ], { fallback: true }, [ "--help" ] ]

      command.raise_unrecognized = "boom"
      exit = assert_raises(SystemExit) { Rails::Command.invoke("boom", [ "ignored" ]) }
      assert_equal 1, exit.status
      assert_includes events, [ command, "help", [], {}, [ "test/command_public_contract_test.rb" ] ]

      output = capture_stdout do
        exit = assert_raises(SystemExit) { Rails::Command.invoke("namespace:fail", []) }
        assert_equal 1, exit.status
      end
      assert_includes output, "Unrecognized command \"fail\""
    end
  end

  test "invoke turns rails new without a path into help" do
    events = []
    with_command_lookup("new" => FakeCommand.new(events, "new" => true)) do
      Rails::Command.invoke("new", [ "new" ])
    end

    assert_equal [ "--help" ], events.first[2]
    assert_equal [ "--help" ], events.first[4]
  end

  private
    class FakeCommand
      attr_accessor :raise_unrecognized

      def initialize(events, commands)
        @events = events
        @commands = commands
      end

      def all_commands
        @commands.merge("help" => true)
      end

      def perform(command_name, args, config)
        raise Rails::Command::UnrecognizedCommandError, raise_unrecognized if raise_unrecognized == command_name

        @events << [ self, command_name, args.dup, config, ARGV.dup ]
      end
    end

    def with_command_lookup(commands)
      singleton = class << Rails::Command; self; end
      original = Rails::Command.method(:find_by_namespace)
      singleton.define_method(:find_by_namespace) do |namespace, command_name = nil|
        commands[namespace.to_s]
      end
      yield
    ensure
      singleton.define_method(:find_by_namespace) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def capture_stdout
      io = StringIO.new
      $stdout = io
      yield
      io.string
    ensure
      $stdout = @original_stdout
    end

    def set_constant(name, value)
      remove_constant(name)
      Object.const_set(name, value)
    end

    def remove_constant(name)
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
end
