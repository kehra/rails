# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module Coders
    class JSONTest < ActiveRecord::TestCase
      def test_returns_nil_if_empty_string_given
        coder = JSON.new
        assert_nil coder.load("")
      end

      def test_returns_nil_if_nil_given
        coder = JSON.new
        assert_nil coder.load(nil)
      end

      def test_coder_with_symbolize_names
        coder = JSON.new(symbolize_names: true)
        assert_equal({ foo: "bar" }, coder.load('{"foo":"bar"}'))
      end

      def test_dump_encodes_values_with_active_support_json_encoder
        coder = JSON.new
        encoder = ActiveSupport::JSON::Encoding.json_encoder.new(escape: false)

        assert_equal encoder.encode("html" => "<tag>"), coder.dump("html" => "<tag>")
      end

      def test_dump_does_not_html_escape
        coder = JSON.new
        assert_equal '{"k":"<>&"}', coder.dump({ "k" => "<>&" })
      end
    end
  end
end
