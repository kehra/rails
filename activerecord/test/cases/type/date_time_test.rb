# frozen_string_literal: true

require "cases/helper"
require "models/task"

module ActiveRecord
  module Type
    class DateTimeTest < ActiveRecord::TestCase
      def test_datetime_seconds_precision_applied_to_timestamp
        p = Task.create!(starting: ::Time.now)
        assert_equal p.starting.usec, p.reload.starting.usec
      end

      test "serialize_cast_value is equivalent to serialize after cast" do
        type = Type::DateTime.new(precision: 1)
        value = type.cast("1999-12-31 12:34:56.789 -1000")

        assert_equal type.serialize(value), type.serialize_cast_value(value)
      end

      test "timezone defaults to Active Record default timezone" do
        old_default_timezone = ActiveRecord.default_timezone
        ActiveRecord.default_timezone = :local

        type = Type::DateTime.new
        assert_equal :local, type.default_timezone
        assert_not type.is_utc?
      ensure
        ActiveRecord.default_timezone = old_default_timezone
      end

      test "timezone option overrides Active Record default timezone" do
        old_default_timezone = ActiveRecord.default_timezone
        ActiveRecord.default_timezone = :local

        type = Type::DateTime.new(timezone: :utc)
        assert_equal :utc, type.default_timezone
        assert_predicate type, :is_utc?
      ensure
        ActiveRecord.default_timezone = old_default_timezone
      end

      test "equality includes timezone" do
        assert_equal Type::DateTime.new(timezone: :utc), Type::DateTime.new(timezone: :utc)
        assert_not_equal Type::DateTime.new(timezone: :utc), Type::DateTime.new(timezone: :local)
      end
    end
  end
end
