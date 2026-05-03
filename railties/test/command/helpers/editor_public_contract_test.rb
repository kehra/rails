# frozen_string_literal: true

require "abstract_unit"
require "rails/command/helpers/editor"
require "tmpdir"

class CommandHelpersEditorPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_env = ENV.to_hash
  end

  teardown do
    ENV.replace(@original_env)
  end

  test "editor prefers visual and falls back to editor" do
    helper = editor_helper

    ENV["VISUAL"] = "visual --wait"
    ENV["EDITOR"] = "editor --wait"
    assert_equal "visual --wait", helper.send(:editor)

    ENV["VISUAL"] = ""
    assert_equal "editor --wait", helper.send(:editor)

    ENV.delete("VISUAL")
    ENV.delete("EDITOR")
    assert_nil helper.send(:editor)
  end

  test "hint is displayed only when no system editor is configured" do
    helper = editor_helper
    ENV["VISUAL"] = ""
    ENV["EDITOR"] = ""

    assert_equal true, helper.send(:display_hint_if_system_editor_not_specified)
    assert_includes helper.messages.join("\n"), "No $VISUAL or $EDITOR"
    assert_includes helper.messages.join("\n"), 'VISUAL="code --wait" bin/rails edit'

    helper.messages.clear
    ENV["EDITOR"] = "cat"
    assert_nil helper.send(:display_hint_if_system_editor_not_specified)
    assert_empty helper.messages
  end

  test "system editor splits command and using_system_editor handles success hint and interrupt" do
    helper = editor_helper
    file = Pathname.new("/tmp/editor contract.txt")
    ENV["VISUAL"] = "code --wait"
    ENV["EDITOR"] = "ignored"

    assert_equal :system_result, helper.send(:system_editor, file)
    assert_equal [ [ "code", "--wait", file.to_s ] ], helper.system_calls

    yielded = false
    assert_equal :yielded, helper.send(:using_system_editor) { yielded = true; :yielded }
    assert yielded

    ENV["VISUAL"] = ""
    ENV["EDITOR"] = ""
    assert_equal true, helper.send(:using_system_editor) { raise "should not run" }

    helper.messages.clear
    ENV["EDITOR"] = "cat"
    assert_equal [ "Aborted changing file: nothing saved." ], helper.send(:using_system_editor) { raise Interrupt }
    assert_equal [ "Aborted changing file: nothing saved." ], helper.messages
  end

  private
    def editor_helper
      Class.new do
        include Rails::Command::Helpers::Editor

        attr_reader :messages, :system_calls

        def initialize
          @messages = []
          @system_calls = []
        end

        def say(message)
          @messages << message
        end

        def executable(subcommand)
          "bin/rails #{subcommand}"
        end

        def current_subcommand
          "edit"
        end

        def system(*args)
          @system_calls << args
          :system_result
        end
      end.new
    end
end
