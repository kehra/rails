# frozen_string_literal: true

require "test_helper"
require "action_text/system_test_helper"

class ActionText::SystemTestHelperUnitTest < ActiveSupport::TestCase
  class FakeEditor
    attr_reader :script, :html

    def execute_script(script, html)
      @script = script
      @html = html
    end
  end

  class Helper
    include ActionText::SystemTestHelper

    attr_reader :locator, :options, :editor

    def initialize
      @editor = FakeEditor.new
    end

    def find(selector, locator = nil, **options)
      raise "unexpected selector: #{selector.inspect}" unless selector == :rich_textarea
      @locator = locator
      @options = options
      @editor
    end
  end

  test "fill_in_rich_textarea delegates to rich text area selector and loads html" do
    helper = Helper.new

    helper.fill_in_rich_textarea "message_content", id: "message_content", with: "Hello <em>world</em>"

    assert_equal "message_content", helper.locator
    assert_equal({ id: "message_content" }, helper.options)
    assert_includes helper.editor.script, "this.editor.loadHTML(arguments[0])"
    assert_equal "Hello <em>world</em>", helper.editor.html
  end

  test "fill_in_rich_text_area alias stringifies nil" do
    helper = Helper.new

    helper.fill_in_rich_text_area with: nil

    assert_nil helper.locator
    assert_equal({}, helper.options)
    assert_equal "", helper.editor.html
  end

  test "rich text area selectors locate editors by supported locators" do
    html = <<~HTML
      <label for="message_content">Message content label</label>
      <input id="trix_input_1" name="message[content]" type="hidden">
      <trix-editor id="message_content" input="trix_input_1" placeholder="Your message here" aria-label="Message content aria-label" role="textbox" contenteditable="true"></trix-editor>
    HTML

    fragment = Capybara.string(html)

    assert_equal "message_content", fragment.find(:rich_textarea, "message_content")[:id]
    assert_equal "message_content", fragment.find(:rich_textarea, "Your message here")[:id]
    assert_equal "message_content", fragment.find(:rich_textarea, "Message content aria-label")[:id]
    assert_equal "message_content", fragment.find(:rich_textarea, "message[content]")[:id]
    assert_equal "message_content", fragment.find(:rich_textarea, "Message content label")[:id]
    assert_equal "message_content", fragment.find(:rich_text_area, "message_content")[:id]
  end

  test "rich text area selectors ignore non editable elements" do
    html = <<~HTML
      <trix-editor id="not_editable" role="textbox"></trix-editor>
      <trix-editor id="editable" role="textbox" contenteditable=""></trix-editor>
    HTML

    assert_equal "editable", Capybara.string(html).find(:rich_textarea)[:id]
  end
end
