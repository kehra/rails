# frozen_string_literal: true

require "test_helper"

class ActionTextTest < ActiveSupport::TestCase
  test "engine exposes default action text configuration" do
    config = Rails.application.config.action_text

    assert_equal :trix, config.editor
    assert_equal({ trix: {} }, config.editors.to_h)
    assert_equal "action-text-attachment", config.attachment_tag_name
    assert_equal "action-text-attachment", ActionText::Attachment.tag_name
    assert_includes Rails.autoloaders.once.dirs, ActionText::Engine.root.join("app/helpers").to_s
    assert_includes Rails.autoloaders.once.dirs, ActionText::Engine.root.join("app/models").to_s
  end

  test "html document classes use HTML5 when available and memoize" do
    ActionText.remove_instance_variable(:@html_document_class) if ActionText.instance_variable_defined?(:@html_document_class)
    ActionText.remove_instance_variable(:@html_document_fragment_class) if ActionText.instance_variable_defined?(:@html_document_fragment_class)

    assert_equal Nokogiri::HTML5::Document, ActionText.html_document_class
    assert_same ActionText.html_document_class, ActionText.html_document_class
    assert_equal Nokogiri::HTML5::DocumentFragment, ActionText.html_document_fragment_class
    assert_same ActionText.html_document_fragment_class, ActionText.html_document_fragment_class
  end

  test "html document classes fall back to HTML4 when HTML5 is unavailable" do
    ActionText.remove_instance_variable(:@html_document_class) if ActionText.instance_variable_defined?(:@html_document_class)
    ActionText.remove_instance_variable(:@html_document_fragment_class) if ActionText.instance_variable_defined?(:@html_document_fragment_class)
    html5 = Nokogiri.send(:remove_const, :HTML5)

    assert_equal Nokogiri::HTML4::Document, ActionText.html_document_class
    assert_equal Nokogiri::HTML4::DocumentFragment, ActionText.html_document_fragment_class
  ensure
    Nokogiri.const_set(:HTML5, html5) if defined?(html5) && !Nokogiri.const_defined?(:HTML5, false)
    ActionText.remove_instance_variable(:@html_document_class) if ActionText.instance_variable_defined?(:@html_document_class)
    ActionText.remove_instance_variable(:@html_document_fragment_class) if ActionText.instance_variable_defined?(:@html_document_fragment_class)
  end
end
