# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class ColumnTest < ActiveRecord::TestCase
      def test_initialize_stores_metadata_and_deserializes_immutable_defaults
        cast_type = Class.new(ActiveModel::Type::Value) do
          def mutable? = false
          def deserialize(value) = "deserialized #{value}"
        end.new
        metadata = SqlTypeMetadata.new(sql_type: "varchar(255)", type: :string, limit: 255)

        column = Column.new("sales_stage", cast_type, "new", metadata, false, "generated_default", collation: "utf8", comment: "workflow")

        assert_equal "sales_stage", column.name
        assert_predicate column.name, :frozen?
        assert_equal cast_type, column.cast_type
        assert_equal metadata, column.sql_type_metadata
        assert_equal "deserialized new", column.default
        assert_not column.null
        assert_equal "generated_default", column.default_function
        assert_equal "utf8", column.collation
        assert_equal "workflow", column.comment
      end

      def test_initialize_keeps_nil_and_mutable_defaults
        mutable_type = Class.new(ActiveModel::Type::Value) do
          def mutable? = true
          def deserialize(_) = raise "mutable defaults should not be deserialized"
        end.new

        assert_nil Column.new("name", mutable_type, nil).default
        assert_equal "raw", Column.new("name", mutable_type, "raw").default
      end

      def test_default_and_type_predicates
        integer_column = column("id", sql_type: "bigint unsigned", type: :integer)
        plain_column = column("name", default: nil, default_function: nil)
        default_column = column("name", default: "anonymous")
        function_column = column("created_at", default_function: "CURRENT_TIMESTAMP")

        assert_predicate integer_column, :bigint?
        assert_not_predicate column("id", sql_type: "integer", type: :integer), :bigint?
        assert_not_predicate plain_column, :has_default?
        assert_predicate default_column, :has_default?
        assert_predicate function_column, :has_default?
        assert_not plain_column.auto_incremented_by_db?
        assert_not plain_column.auto_populated?
        assert_equal "CURRENT_TIMESTAMP", function_column.auto_populated?
        assert_not plain_column.virtual?
      end

      def test_human_name_uses_active_record_attribute_translation
        assert_equal "Sales stage", column("sales_stage").human_name
      end

      def test_encode_and_init_with_round_trip_column_state
        original = column("name", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name")
        coder = {}

        original.encode_with(coder)
        decoded = Column.allocate
        decoded.init_with(coder)

        assert_equal original, decoded
        assert_equal original.hash, decoded.hash
      end

      def test_equality_compares_all_column_attributes
        original = column("name", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name")
        same = column("name", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name")

        assert_equal original, same
        assert_equal original.hash, same.hash
        assert_not_equal original, Object.new

        different_columns = [
          column("title", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name"),
          column("name", cast_type: ActiveModel::Type::Integer.new, default: 1, null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name", sql_type: "integer", type: :integer),
          column("name", default: "named", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name"),
          column("name", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name", sql_type: "text"),
          column("name", default: "anonymous", null: true, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "display name"),
          column("name", default: "anonymous", null: false, default_function: "upper('anonymous')", collation: "utf8", comment: "display name"),
          column("name", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "latin1", comment: "display name"),
          column("name", default: "anonymous", null: false, default_function: "lower('ANONYMOUS')", collation: "utf8", comment: "nickname"),
        ]

        different_columns.each do |other|
          assert_not_equal original, other
        end
      end

      def test_null_column_initializes_without_type_metadata_or_default
        column = NullColumn.new("missing_attribute")

        assert_equal "missing_attribute", column.name
        assert_nil column.cast_type
        assert_nil column.default
        assert_nil column.sql_type_metadata
        assert column.null
      end

      private
        def column(name, cast_type: ActiveModel::Type::String.new, default: nil, sql_type: "varchar", type: :string, null: true, default_function: nil, collation: nil, comment: nil)
          Column.new(name, cast_type, default, SqlTypeMetadata.new(sql_type: sql_type, type: type), null, default_function, collation: collation, comment: comment)
        end
    end
  end
end
