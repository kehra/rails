# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module Type
    class SerializedTest < ActiveRecord::TestCase
      Coder = Struct.new(:object_class, :asserted_values, keyword_init: true) do
        def dump(value)
          value&.to_json
        end

        def load(value)
          value && JSON.parse(value)
        end

        def assert_valid_value(value, action:)
          asserted_values << [value, action]
        end
      end

      test "deserialize returns the coder default value unchanged" do
        assert_nil type.deserialize(nil)
      end

      test "deserialize loads serialized values through the coder" do
        assert_equal({ "key" => "value" }, type.deserialize('{"key":"value"}'))
      end

      test "serialize returns nil for nil and coder default values" do
        assert_nil type.serialize(nil)
        assert_nil type.serialize(coder.load(nil))

        type_with_array_default = Serialized.new(subtype, ArrayDefaultCoder)
        assert_nil type_with_array_default.serialize([])
      end

      test "serialize dumps through the coder and subtype" do
        assert_equal '{"key":"value"}', type.serialize({ "key" => "value" })
      end

      test "changed in place is false for nil value" do
        assert_not type.changed_in_place?('{"key":"value"}', nil)
      end

      test "changed in place compares serialized representation by default" do
        assert_not type.changed_in_place?('{"key":"value"}', { "key" => "value" })
        assert type.changed_in_place?('{"key":"old"}', { "key" => "new" })
        assert type.changed_in_place?(nil, { "key" => "value" })
      end

      test "changed in place compares deserialized value when comparable" do
        comparable_type = Serialized.new(subtype, coder, comparable: true)

        assert_not comparable_type.changed_in_place?('{"a":1,"b":2}', { "b" => 2, "a" => 1 })
        assert comparable_type.changed_in_place?('{"a":1}', { "a" => 2 })
      end

      test "binary subtype wraps encoded payload in binary data" do
        binary_type = Serialized.new(ActiveModel::Type::Binary.new, coder)

        assert_instance_of ActiveModel::Type::Binary::Data, binary_type.send(:encoded, { "key" => "value" })
      end

      test "encoded returns nil for non nil coder default values" do
        type_with_array_default = Serialized.new(subtype, ArrayDefaultCoder)

        assert_nil type_with_array_default.send(:encoded, [])
      end

      test "accessor uses indifferent hash accessor" do
        assert_equal ActiveRecord::Store::IndifferentHashAccessor, type.accessor
      end

      test "assert valid value delegates to coder when available" do
        type.assert_valid_value({ "key" => "value" })

        assert_equal [[{ "key" => "value" }, "serialize"]], coder.asserted_values
      end

      test "assert valid value is optional for coders" do
        assert_nil Serialized.new(subtype, PlainCoder).assert_valid_value({ "key" => "value" })
      end

      test "force equality applies to coder object class" do
        assert type.force_equality?({ "key" => "value" })
        assert_not type.force_equality?(["value"])
      end

      test "serialized is true" do
        assert_predicate type, :serialized?
      end

      test "text type reports text" do
        assert_equal :text, Text.new.type
      end

      private
        def type
          @type ||= Serialized.new(subtype, coder)
        end

        def subtype
          @subtype ||= ActiveModel::Type::String.new
        end

        def coder
          @coder ||= Coder.new(object_class: Hash, asserted_values: [])
        end

        module ArrayDefaultCoder
          def self.dump(value)
            value.to_json
          end

          def self.load(value)
            value ? JSON.parse(value) : []
          end
        end

        module PlainCoder
          def self.dump(value)
            value&.to_json
          end

          def self.load(value)
            value && JSON.parse(value)
          end
        end
    end
  end
end
