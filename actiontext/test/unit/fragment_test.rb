# frozen_string_literal: true

require "test_helper"

class ActionText::FragmentTest < ActiveSupport::TestCase
  test "wrap handles fragments nokogiri fragments and html" do
    fragment = ActionText::Fragment.from_html("<p>Hello</p>")

    assert_same fragment, ActionText::Fragment.wrap(fragment)
    assert_equal "<p>Hello</p>", ActionText::Fragment.wrap(fragment.source).to_html
    assert_equal "<p>Hello</p>", ActionText::Fragment.wrap("<p>Hello</p>").to_s
  end

  test "find update replace and conversions" do
    fragment = ActionText::Fragment.from_html('<p>Hello <strong>world</strong></p><br>')

    assert_equal ["p"], fragment.find_all("p").map(&:name)
    assert_equal ["p", "br"], fragment.deconstruct.map(&:name)
    assert_equal "Hello world", fragment.to_plain_text.strip
    assert_equal "Hello **world**", fragment.to_markdown.strip

    updated = fragment.update { |source| source.css("strong").each { |node| node.content = "Rails" } }
    replaced = updated.replace("strong") { |node| "<em>#{node.text}</em>" }
    unchanged = replaced.replace("em") { |node| node }

    assert_equal "<p>Hello <strong>world</strong></p><br>", fragment.to_html
    assert_equal "<p>Hello <em>Rails</em></p><br>", replaced.to_html
    assert_equal replaced.to_html, unchanged.to_html
  end
end
