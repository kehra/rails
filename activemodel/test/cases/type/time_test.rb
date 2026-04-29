# frozen_string_literal: true

require "cases/helper"
require "active_support/core_ext/time/conversions"

module ActiveModel
  module Type
    class TimeTest < ActiveModel::TestCase
      def test_type_cast_time
        type = Type::Time.new
        assert_equal :time, type.type
        assert_nil type.cast(nil)
        assert_nil type.cast("")
        assert_nil type.cast("ABC")
        assert_nil type.cast(" " * 129)

        time_string = ::Time.now.utc.strftime("%T")
        assert_equal time_string, type.cast(time_string).strftime("%T")

        assert_equal ::Time.utc(2000,  1,  1, 16, 45, 54), type.cast("2015-06-13T19:45:54+03:00")
        assert_equal ::Time.utc(1999, 12, 31, 21,  7,  8), type.cast("06:07:08+09:00")
        assert_equal ::Time.utc(2000,  1,  1, 16, 45, 54), type.cast(4 => 16, 5 => 45, 6 => 54)
        assert_equal ::Time.utc(2000,  1,  1, 3, 30, 0), type.cast("2023-01-01T00:00:00-03:30")
      end

      def test_type_cast_for_schema
        type = Type::Time.new

        assert_equal '"2000-01-01 01:02:03"', type.type_cast_for_schema(::Time.utc(2000, 1, 1, 1, 2, 3))
      end

      def test_user_input_in_time_zone
        ::Time.use_zone("Pacific Time (US & Canada)") do
          type = Type::Time.new
          assert_nil type.user_input_in_time_zone(nil)
          assert_nil type.user_input_in_time_zone("")
          assert_nil type.user_input_in_time_zone("ABC")
          assert_nil type.user_input_in_time_zone(" " * 129)

          offset = ::Time.zone.formatted_offset
          time_string = "2015-02-09T19:45:54#{offset}"

          assert_equal 19, type.user_input_in_time_zone(time_string).hour
          assert_equal offset, type.user_input_in_time_zone(time_string).formatted_offset
        end
      end

      test "serialize_cast_value is equivalent to serialize after cast" do
        type = Type::Time.new(precision: 1)
        value = type.cast("1999-12-31T12:34:56.789-10:00")

        assert_equal type.serialize(value), type.serialize_cast_value(value)
      end

      test "serialize_cast_value preserves non time values and already utc times" do
        type = Type::Time.new(precision: 3)
        time = ::Time.utc(2000, 1, 1, 1, 2, 3, 123_000)

        assert_equal "raw", type.serialize_cast_value("raw")
        assert_equal time, type.serialize_cast_value(time)
      end

      test "serialize_cast_value converts to local time outside UTC" do
        with_timezone_config default: "Pacific Time (US & Canada)" do
          type = Type::Time.new
          time = ::Time.utc(2000, 1, 1, 1, 2, 3)

          assert_equal time.getlocal, type.serialize_cast_value(time)
        end
      end

      test "seconds precision leaves values unchanged when rounding is unnecessary" do
        no_precision_type = Type::Time.new
        precision_type = Type::Time.new(precision: 3)
        time = ::Time.utc(2000, 1, 1, 1, 2, 3, 123_000)

        assert_equal time, no_precision_type.send(:apply_seconds_precision, time)
        assert_equal time, precision_type.send(:apply_seconds_precision, time)
      end

      test "multiparameter values use local time when default zone is not UTC" do
        with_timezone_config default: "Pacific Time (US & Canada)" do
          type = Type::Time.new
          value = type.cast(4 => 1, 5 => 2, 6 => 3)

          assert_equal 1, value.hour
          assert_equal 2, value.min
          assert_equal 3, value.sec
          assert_not type.send(:is_utc?)
          assert_equal :local, type.send(:default_timezone)
        end
      end

      private
        def with_timezone_config(default:)
          old_zone_default = ::Time.zone_default
          ::Time.zone_default = ::Time.find_zone(default)
          yield
        ensure
          ::Time.zone_default = old_zone_default
        end
    end
  end
end
