# frozen_string_literal: true

require_relative "xml_mini_engine_test"

XMLMiniEngineTest.run_with_gem("libxml") do
  class LibXMLSAXEngineTest < XMLMiniEngineTest
    test "third repeated child appends to existing array" do
      hash = ActiveSupport::XmlMini.parse("<root><item>a</item><item>b</item><item>c</item></root>")

      assert_equal ["a", "b", "c"], hash["root"]["item"].map { |item| item["__content__"] }
    end

    test "start element leaves existing scalar value unchanged" do
      builder = ActiveSupport::XmlMini_LibXMLSAX::HashBuilder.new
      builder.on_start_document
      builder.current_hash["root"] = "existing"
      builder.on_start_element("root")

      assert_equal "existing", builder.hash["root"]
    end

    private
      def engine
        "LibXMLSAX"
      end

      def expansion_attack_error
        LibXML::XML::Error
      end
  end
end
