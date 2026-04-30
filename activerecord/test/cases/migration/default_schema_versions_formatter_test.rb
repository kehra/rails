# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  class Migration
    class DefaultSchemaVersionsFormatterTest < ActiveRecord::TestCase
      class FakeSchemaMigration
        def table_name = "schema_versions"
      end

      class FakePool
        def schema_migration = FakeSchemaMigration.new
      end

      class FakeConnection
        def pool = FakePool.new

        def quote_table_name(name)
          "`#{name}`"
        end

        def quote(value)
          "'#{value}'"
        end
      end

      def test_format_schema_versions_array_in_reverse_order
        formatter = DefaultSchemaVersionsFormatter.new(FakeConnection.new)

        assert_equal <<~SQL.chomp, formatter.format(["20240101010101", "20240202020202"])
          INSERT INTO `schema_versions` (version) VALUES
          ('20240202020202'),
          ('20240101010101');
        SQL
      end

      def test_format_single_schema_version
        formatter = DefaultSchemaVersionsFormatter.new(FakeConnection.new)

        assert_equal "INSERT INTO `schema_versions` (version) VALUES ('20240101010101');", formatter.format("20240101010101")
      end
    end
  end
end
