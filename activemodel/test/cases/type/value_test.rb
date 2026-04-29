# frozen_string_literal: true

require "cases/helper"
require "active_support/core_ext/object/json"

module ActiveModel
  module Type
    class ValueTest < ActiveModel::TestCase
      def test_type_equality
        assert_equal Type::Value.new, Type::Value.new
        assert_not_equal Type::Value.new, Type::Integer.new
        assert_not_equal Type::Value.new(precision: 1), Type::Value.new(precision: 2)
      end

      test "base value defaults" do
        type = Type::Value.new(precision: 1, scale: 2, limit: 3)

        assert type.serializable?(:value)
        assert_nil type.type
        assert_nil type.cast(nil)
        assert_equal :value, type.cast(:value)
        assert_equal :value, type.deserialize(:value)
        assert_equal :value, type.serialize(:value)
        assert_equal ":value", type.type_cast_for_schema(:value)
        assert_not type.binary?
        assert type.changed?(:old, :new, :raw)
        assert_not type.changed?(:same, :same, :raw)
        assert_not type.changed_in_place?(:raw, :new)
        assert_not type.value_constructed_by_mass_assignment?(:value)
        assert_not type.force_equality?(:value)
        assert_equal :value, type.map(:value) { |v| v.to_s }
        assert_equal [Type::Value, 1, 2, 3].hash, type.hash
        assert_nil type.assert_valid_value(:value)
        assert_not type.serialized?
        assert_predicate type, :mutable?
      end

      def test_as_json_not_defined
        assert_raises NoMethodError do
          Type::Value.new.as_json
        end
      end

      test "mutable helper casts through serialize and deserialize" do
        type = Class.new(Type::Value) do
          include Type::Helpers::Mutable

          def serialize(value)
            value&.upcase
          end

          def deserialize(value)
            value&.downcase
          end
        end.new

        assert_predicate type, :mutable?
        assert_equal "value", type.cast("value")
        assert_not type.changed_in_place?("VALUE", "value")
        assert type.changed_in_place?("OLD", "value")
      end
    end
  end
end
