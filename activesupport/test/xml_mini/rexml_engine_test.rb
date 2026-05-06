# frozen_string_literal: true

require_relative "xml_mini_engine_test"
require "rexml/document"

class REXMLEngineTest < XMLMiniEngineTest
  def test_default_is_rexml
    assert_equal ActiveSupport::XmlMini_REXML, ActiveSupport::XmlMini.backend
  end

  def test_parse_from_empty_string
    assert_equal({}, ActiveSupport::XmlMini.parse(""))
  end

  def test_parse_from_frozen_string
    xml_string = "<root></root>"
    assert_equal({ "root" => {} }, ActiveSupport::XmlMini.parse(xml_string))
  end

  def test_parse_without_valid_root_raises
    assert_raises(REXML::ParseException) do
      ActiveSupport::XmlMini.parse("<!-- no root -->")
    end
  end

  def test_document_too_deep_raises
    old_depth = ActiveSupport::XmlMini.depth
    ActiveSupport::XmlMini.depth = 0

    assert_raises(REXML::ParseException) do
      ActiveSupport::XmlMini.parse("<root/>")
    end
  ensure
    ActiveSupport::XmlMini.depth = old_depth
  end

  def test_third_repeated_child_appends_to_existing_array
    hash = ActiveSupport::XmlMini.parse("<root><item>a</item><item>b</item><item>c</item></root>")

    assert_equal ["a", "b", "c"], hash["root"]["item"].map { |item| item["__content__"] }
  end

  def test_array_value_is_wrapped_when_merged
    hash = ActiveSupport::XmlMini_REXML.send(:merge!, {}, "items", ["a"])

    assert_equal({ "items" => [["a"]] }, hash)
  end

  private
    def engine
      "REXML"
    end

    def expansion_attack_error
      RuntimeError
    end
end
