# frozen_string_literal: true

require "cases/helper"
require "active_support/core_ext/date/conversions"

module ActiveModel
  module Type
    class DateTest < ActiveModel::TestCase
      def test_type_cast_date
        type = Type::Date.new
        assert_equal :date, type.type
        assert_nil type.cast(nil)
        assert_nil type.cast("")
        assert_nil type.cast(" ")
        assert_nil type.cast("ABC")
        assert_nil type.cast(" " * 129)

        now = ::Time.now.utc
        date = ::Date.new(now.year, now.mon, now.mday)
        values_hash = { 1 => now.year, 2 => now.mon, 3 => now.mday }
        date_string = now.strftime("%F")
        assert_equal date_string, type.cast(date_string).strftime("%F")
        assert_equal date_string, type.cast(values_hash).strftime("%F")
        value = Object.new
        value.define_singleton_method(:to_date) { date }
        assert_equal date, type.cast(value)
      end

      def test_type_cast_for_schema
        type = Type::Date.new

        assert_equal '"2000-01-02"', type.type_cast_for_schema(::Date.new(2000, 1, 2))
      end

      def test_returns_correct_year
        type = Type::Date.new

        time = ::Time.utc(1, 1, 1)
        date = ::Date.new(time.year, time.mon, time.mday)

        values_hash_for_multiparameter_assignment = { 1 => 1, 2 => 1, 3 => 1 }

        assert_equal date, type.cast(values_hash_for_multiparameter_assignment)
      end

      def test_multiparameter_helpers
        type = Type::Date.new
        values_hash = { 1 => 2000, 2 => 1, 3 => 2 }

        assert_equal ::Date.new(2000, 1, 2), type.cast(values_hash)
        assert_nil type.cast(1 => 2000)
        assert_equal ::Date.new(2000, 1, 2), type.assert_valid_value(values_hash)
        assert_nil type.assert_valid_value("2000-01-02")
        assert type.value_constructed_by_mass_assignment?(values_hash)
        assert_not type.value_constructed_by_mass_assignment?("2000-01-02")
        assert_equal ::Date.new(2000, 1, 2), type.serialize_cast_value(::Date.new(2000, 1, 2))
      end

      def test_type_cast_from_value_responding_to_to_date
        type = Type::Date.new

        assert_equal ::Date.new(1999, 12, 31), type.cast(::Time.utc(1999, 12, 31, 23, 59, 59))
        assert_equal ::Date.new(2008, 2, 10), type.cast(::Date.new(2008, 2, 10))
      end

      def test_type_cast_from_non_iso_string
        type = Type::Date.new

        assert_equal ::Date.new(2008, 2, 1), type.cast("1 Feb 2008")
      end

      def test_type_cast_from_invalid_date_string_returns_nil
        type = Type::Date.new

        assert_nil type.cast("2008-02-31")
      end

      def test_type_cast_returns_non_date_values_unchanged
        type = Type::Date.new

        assert_equal 42, type.cast(42)
      end
    end
  end
end
