# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module Type
    class JsonTest < ActiveRecord::TestCase
      test "type is json" do
        assert_equal :json, type.type
      end

      test "deserialize decodes JSON strings" do
        assert_equal({ "key" => [1, true] }, type.deserialize('{"key":[1,true]}'))
      end

      test "deserialize returns non string values unchanged" do
        value = { "key" => "value" }

        assert_same value, type.deserialize(value)
      end

      test "deserialize reports invalid JSON and returns nil" do
        assert_error_reported(JSON::ParserError) do
          assert_nil type.deserialize("---")
        end
      end

      test "serialize encodes without HTML escaping" do
        assert_equal '{"key":"<value>&"}', type.serialize({ "key" => "<value>&" })
      end

      test "serialize returns nil for nil values" do
        assert_nil type.serialize(nil)
      end

      test "changed in place compares deserialized old value with new value" do
        assert_not type.changed_in_place?('{"key":"value"}', { "key" => "value" })
        assert type.changed_in_place?('{"key":"old"}', { "key" => "new" })
      end

      test "accessor uses string keyed hash accessor" do
        assert_equal ActiveRecord::Store::StringKeyedHashAccessor, type.accessor
      end

      private
        def type
          @type ||= Json.new
        end
    end
  end
end
