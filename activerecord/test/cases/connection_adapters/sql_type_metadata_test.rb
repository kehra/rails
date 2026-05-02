# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class SqlTypeMetadataTest < ActiveRecord::TestCase
      def test_initialize_exposes_sql_type_attributes_and_deduplicates_sql_type
        metadata = SqlTypeMetadata.new(sql_type: "varchar(255)", type: :string, limit: 255, precision: 10, scale: 2)

        assert_equal "varchar(255)", metadata.sql_type
        assert_predicate metadata.sql_type, :frozen?
        assert_equal :string, metadata.type
        assert_equal 255, metadata.limit
        assert_equal 10, metadata.precision
        assert_equal 2, metadata.scale
      end

      def test_equality_and_hash_include_all_attributes
        original = SqlTypeMetadata.new(sql_type: "decimal(10,2)", type: :decimal, limit: 8, precision: 10, scale: 2)
        same = SqlTypeMetadata.new(sql_type: "decimal(10,2)", type: :decimal, limit: 8, precision: 10, scale: 2)

        assert_equal original, same
        assert_equal original.hash, same.hash
        assert original.eql?(same)
        assert_not_equal original, Object.new

        different_metadata = [
          SqlTypeMetadata.new(sql_type: "numeric(10,2)", type: :decimal, limit: 8, precision: 10, scale: 2),
          SqlTypeMetadata.new(sql_type: "decimal(10,2)", type: :float, limit: 8, precision: 10, scale: 2),
          SqlTypeMetadata.new(sql_type: "decimal(10,2)", type: :decimal, limit: 4, precision: 10, scale: 2),
          SqlTypeMetadata.new(sql_type: "decimal(10,2)", type: :decimal, limit: 8, precision: 12, scale: 2),
          SqlTypeMetadata.new(sql_type: "decimal(10,2)", type: :decimal, limit: 8, precision: 10, scale: 3),
        ]

        different_metadata.each do |metadata|
          assert_not_equal original, metadata
        end
      end

      def test_deduplicable_registry_reuses_equivalent_instances
        first = SqlTypeMetadata.new(sql_type: "integer", type: :integer)
        second = SqlTypeMetadata.new(sql_type: "integer", type: :integer)

        assert_same first, second
        assert_same first, -first
      end
    end
  end
end
