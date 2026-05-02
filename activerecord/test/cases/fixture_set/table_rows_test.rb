# frozen_string_literal: true

require "cases/helper"
require "active_record/fixture_set/table_rows"

module ActiveRecord
  class FixtureSet
    class TableRowsTest < ActiveRecord::TestCase
      class FakeFixture
        def initialize(attributes)
          @attributes = attributes
        end

        def to_hash
          @attributes.dup
        end
      end

      def test_builds_rows_and_hash_with_local_timezone
        original_timezone = ActiveRecord.default_timezone
        ActiveRecord.default_timezone = :local

        rows = TableRows.new(
          "books",
          model_class: nil,
          fixtures: {
            "one" => FakeFixture.new("title" => "Book One"),
            "two" => FakeFixture.new("title" => "Book Two"),
          },
        )

        assert_nil rows.model_class
        assert_instance_of ModelMetadata, rows.model_metadata
        assert_equal({
          "books" => [
            { "title" => "Book One" },
            { "title" => "Book Two" },
          ]
        }, rows.to_hash)
      ensure
        ActiveRecord.default_timezone = original_timezone
      end
    end
  end
end
