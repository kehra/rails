# frozen_string_literal: true

require "test_helper"

class ActionTextTest < ActiveSupport::TestCase
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
