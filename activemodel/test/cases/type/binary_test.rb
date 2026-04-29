# frozen_string_literal: true

require "cases/helper"

module ActiveModel
  module Type
    class BinaryTest < ActiveModel::TestCase
      def test_type_cast_binary
        type = Type::Binary.new

        assert_equal :binary, type.type
        assert_predicate type, :binary?
        assert_nil type.cast(nil)
        assert_equal 1, type.cast(1)

        assert_equal "1", type.cast("1")
        assert_equal Encoding::BINARY, type.cast("1").encoding

        assert_equal "ƒée".b, type.cast("ƒée")
        assert_not_equal "ƒée", type.cast("ƒée")
      end

      def test_serialize_binary_strings
        type = Type::Binary.new
        assert_nil type.serialize(nil)
        assert_equal "ƒée".b, type.serialize("ƒée")
        assert_not_equal "ƒée", type.serialize("ƒée")
      end

      def test_cast_serialized_data
        type = Type::Binary.new
        data = type.serialize("ƒée")

        assert_equal "ƒée".b, type.cast(data)
      end

      def test_changed_in_place
        type = Type::Binary.new
        raw_value = type.serialize("old")

        assert_not type.changed_in_place?(raw_value, "old".b)
        assert type.changed_in_place?(raw_value, "new".b)
      end
    end
  end
end
