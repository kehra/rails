# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "tmpdir"

class CommandBehaviorPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_shell = Thor::Base.shell
    @original_load_path = $LOAD_PATH.dup
    @original_features = $LOADED_FEATURES.dup
    @tmpdir = Dir.mktmpdir("command-behavior")
  end

  teardown do
    Thor::Base.shell = @original_shell
    $LOAD_PATH.replace(@original_load_path)
    $LOADED_FEATURES.replace(@original_features)
    FileUtils.rm_rf(@tmpdir)
  end

  test "no color subclasses list printing and namespace path conversion expose behavior contracts" do
    Thor::Base.shell = Thor::Shell::Color
    Rails::Command.no_color!
    assert_equal Thor::Shell::Basic, Thor::Base.shell

    assert_same Rails::Command.subclasses, Rails::Command.subclasses
    assert_kind_of Array, Rails::Command.subclasses

    assert_equal [ "admin/users/users", "admin/users", "plain/plain", "plain" ],
      Rails::Command.send(:namespaces_to_paths, [ "admin:users", "plain" ])

    assert_equal "", capture_stdout { Rails::Command.send(:print_list, "demo", []) }
    output = capture_stdout { Rails::Command.send(:print_list, "demo", [ "one", "two" ]) }
    assert_equal "Demo:\n  one\n  two\n\n", output
  end

  test "lookup loads matching command files ignores missing files and reraises unrelated load errors" do
    FileUtils.mkdir_p(File.join(@tmpdir, "commands/demo"))
    File.write(File.join(@tmpdir, "commands/demo/demo_command.rb"), "$command_behavior_loaded = true\n")
    FileUtils.mkdir_p(File.join(@tmpdir, "commands/mismatch"))
    File.write(File.join(@tmpdir, "commands/mismatch/mismatch_command.rb"), "raise LoadError, 'cannot load such file -- totally/different'\n")
    $LOAD_PATH.unshift(@tmpdir)

    Rails::Command.send(:lookup, [ "demo" ])
    assert $command_behavior_loaded

    assert_nothing_raised do
      Rails::Command.send(:lookup, [ "missing" ])
    end
    assert_raise(LoadError) do
      Rails::Command.send(:lookup, [ "mismatch" ])
    end
  ensure
    $command_behavior_loaded = false
  end

  test "lookup warns for command files that raise while loading and lookup bang scans load path" do
    FileUtils.mkdir_p(File.join(@tmpdir, "commands/broken"))
    File.write(File.join(@tmpdir, "commands/broken/broken_command.rb"), "raise 'broken command load'\n")
    FileUtils.mkdir_p(File.join(@tmpdir, "rails/commands/scanned"))
    File.write(File.join(@tmpdir, "rails/commands/scanned/scanned_command.rb"), "$command_behavior_scanned = true\n")
    $LOAD_PATH.unshift(@tmpdir)

    warning = capture_stderr do
      Rails::Command.send(:lookup, [ "broken" ])
    end
    assert_includes warning, "Could not load command"
    assert_includes warning, "broken command load"

    Rails::Command.send(:lookup!)
    assert $command_behavior_scanned
  ensure
    $command_behavior_scanned = false
  end

  private
    def capture_stdout
      original = $stdout
      io = StringIO.new
      $stdout = io
      yield
      io.string
    ensure
      $stdout = original
    end

    def capture_stderr
      original = $stderr
      io = StringIO.new
      $stderr = io
      yield
      io.string
    ensure
      $stderr = original
    end
end
