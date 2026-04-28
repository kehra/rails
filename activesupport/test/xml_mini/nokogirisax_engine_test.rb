# frozen_string_literal: true

require_relative "xml_mini_engine_test"

XMLMiniEngineTest.run_with_gem("nokogiri") do
  class NokogiriSAXEngineTest < XMLMiniEngineTest
    test "third repeated child appends to existing array" do
      hash = ActiveSupport::XmlMini.parse("<root><item>a</item><item>b</item><item>c</item></root>")

      assert_equal ["a", "b", "c"], hash["root"]["item"].map { |item| item["__content__"] }
    end

    test "start element leaves existing scalar value unchanged" do
      builder = ActiveSupport::XmlMini_NokogiriSAX::HashBuilder.new
      builder.start_document
      builder.current_hash["root"] = "existing"
      builder.start_element("root")

      assert_equal "existing", builder.hash["root"]
    end

    test "end document raises when parse stack is not empty" do
      builder = ActiveSupport::XmlMini_NokogiriSAX::HashBuilder.new
      builder.start_document
      builder.start_element("root")

      assert_raises(RuntimeError) { builder.end_document }
    end

    private
      def engine
        "NokogiriSAX"
      end

      def expansion_attack_error
        RuntimeError
      end
  end
end
