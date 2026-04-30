# frozen_string_literal: true

require_relative "xml_mini_engine_test"

XMLMiniEngineTest.run_with_gem("libxml") do
  class LibxmlEngineTest < XMLMiniEngineTest
    def setup
      super
      LibXML::XML::Error.set_handler(&lambda { |error| }) # silence libxml, exceptions will do
    end

    test "third repeated child appends to existing array" do
      hash = ActiveSupport::XmlMini.parse("<root><item>a</item><item>b</item><item>c</item></root>")

      assert_equal ["a", "b", "c"], hash["root"]["item"].map { |item| item["__content__"] }
    end

    test "node conversion keeps nonblank content alongside attributes" do
      hash = ActiveSupport::XmlMini.parse('<root id="1">text</root>')

      assert_equal({ "id" => "1", "__content__" => "text" }, hash["root"])
    end

    test "node conversion keeps nonblank content alongside children" do
      hash = ActiveSupport::XmlMini.parse('<root>text<item/></root>')

      assert_equal "text", hash["root"]["__content__"]
      assert_equal({}, hash["root"]["item"])
    end

    test "node conversion leaves existing scalar value unchanged" do
      node = LibXML::XML::Parser.string("<root>text</root>").parse.root

      assert_equal({ "root" => "existing" }, node.to_hash("root" => "existing"))
    end

    private
      def engine
        "LibXML"
      end

      def expansion_attack_error
        LibXML::XML::Error
      end
  end
end
