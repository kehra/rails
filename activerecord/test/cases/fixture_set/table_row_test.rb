# frozen_string_literal: true

require "cases/helper"
require "active_record/fixture_set/table_row"

module ActiveRecord
  class FixtureSet
    class TableRowTest < ActiveRecord::TestCase
      FakeType = Struct.new(:type)

      class FakeFixture
        def initialize(attributes)
          @attributes = attributes
        end

        def to_hash
          @attributes.dup
        end
      end

      def test_reflection_proxy_exposes_join_table_name_and_primary_key_type
        association = Struct.new(:join_table, :name, :klass).new("posts_tags", :tags, fake_model_class)
        proxy = TableRow::ReflectionProxy.new(association)

        assert_equal "posts_tags", proxy.join_table
        assert_equal :tags, proxy.name
        assert_equal :integer, proxy.primary_key_type
      end

      def test_polymorphic_belongs_to_without_type_suffix_sets_only_foreign_key
        table_rows = fake_table_rows(model_class: fake_model_class)
        row = TableRow.new(
          FakeFixture.new("parent" => "welcome"),
          table_rows: table_rows,
          label: "child",
          now: Time.utc(2026, 5, 2),
        ).to_hash

        assert_equal ActiveRecord::FixtureSet.identify("welcome", :integer), row["parent_id"]
        assert_nil row["parent_type"]
      end

      def test_add_join_records_supports_composite_rhs_key
        table_row = TableRow.allocate
        table_rows = fake_table_rows(model_class: fake_model_class)
        table_row.instance_variable_set(:@table_rows, table_rows)
        table_row.instance_variable_set(:@row, { "id" => 42, "tags" => "red" })

        table_row.send(:add_join_records, composite_rhs_has_many_through_association)

        tag_key = ActiveRecord::FixtureSet.composite_identify("red", ["tag_tenant_id", "tag_id"])
        assert_equal [
          {
            "tag_tenant_id" => tag_key["tag_tenant_id"],
            "tag_id" => tag_key["tag_id"],
            "post_id" => 42,
            "created_at" => nil,
          }
        ], table_rows.tables["posts_tags"]
      end

      private
        def fake_model_class
          @fake_model_class ||= Class.new do
            def self.primary_key
              "id"
            end

            def self.type_for_attribute(_column_name)
              ActiveRecord::FixtureSet::TableRowTest::FakeType.new(:integer)
            end

            def self.record_timestamps
              false
            end

            def self.composite_primary_key?
              false
            end

            def self.defined_enums
              {}
            end

            def self._reflections
              { "parent" => ActiveRecord::FixtureSet::TableRowTest.polymorphic_parent_association }
            end
          end
        end

        def fake_table_rows(model_class:)
          metadata = Struct.new(:primary_key_name, :inheritance_column_name, :timestamp_column_names) do
            def has_column?(_column_name)
              true
            end

            def column_type(_column_name)
              :integer
            end
          end.new("id", nil, [])

          Struct.new(:model_class, :model_metadata, :tables).new(model_class, metadata, Hash.new { |h, table| h[table] = [] })
        end

        def composite_rhs_has_many_through_association
          Struct.new(:name, :join_table, :primary_key_type, :lhs_key, :rhs_key, :timestamp_column_names).new(
            :tags,
            "posts_tags",
            :integer,
            "post_id",
            ["tag_tenant_id", "tag_id"],
            ["created_at"],
          )
        end

        def self.polymorphic_parent_association
          Struct.new(:macro, :name, :join_foreign_key, :polymorphic?, :join_foreign_type, :join_primary_key, :klass, keyword_init: true).new(
            macro: :belongs_to,
            name: :parent,
            join_foreign_key: "parent_id",
            polymorphic?: true,
            join_foreign_type: "parent_type",
            join_primary_key: "id",
            klass: nil,
          )
        end
    end
  end
end
