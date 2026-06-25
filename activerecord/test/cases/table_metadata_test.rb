# frozen_string_literal: true

require "cases/helper"
require "models/developer"
require "models/customer"
require "models/mentor"
require "models/tagging"

module ActiveRecord
  class TableMetadataTest < ActiveSupport::TestCase
    test "#associated_table creates the right type caster for joined table with different association name" do
      base_table_metadata = TableMetadata.new(AuditRequiredDeveloper, Arel::Table.new(name: "developers"))

      associated_table_metadata = base_table_metadata.associated_table("audit_logs")

      assert_equal ActiveRecord::Type::String, associated_table_metadata.arel_table.type_for_attribute(:message).class
    end

    test "delegates metadata lookups to the model when present" do
      table_metadata = TableMetadata.new(Customer, Customer.arel_table)

      assert_equal Customer.primary_key, table_metadata.primary_key
      assert table_metadata.has_column?("name")
      assert_not table_metadata.has_column?("missing")
      assert_equal Customer.reflect_on_aggregation(:address), table_metadata.reflect_on_aggregation(:address)
      assert_equal Customer.reflect_on_aggregation(:address), table_metadata.aggregated_with?(:address)
      assert_equal Customer.predicate_builder.with(table_metadata).class, table_metadata.predicate_builder.class
    end

    test "handles missing model for metadata lookups" do
      table_metadata = TableMetadata.new(nil, Arel::Table.new(name: "unknown_table"))

      assert_nil table_metadata.primary_key
      assert_nil table_metadata.has_column?("id")
      assert_nil table_metadata.associated_with(:anything)
      assert_nil table_metadata.reflect_on_aggregation(:anything)
      assert_instance_of PredicateBuilder, table_metadata.predicate_builder
    end

    test "#associated_table returns self for the current table" do
      table_metadata = TableMetadata.new(Developer, Developer.arel_table)

      assert_same table_metadata, table_metadata.associated_table("developers")
    end

    test "#associated_table singularizes association names" do
      table_metadata = TableMetadata.new(Developer, Developer.arel_table)

      associated_table_metadata = table_metadata.associated_table("mentors")

      assert_equal "mentors", associated_table_metadata.arel_table.name
      assert_equal Mentor, associated_table_metadata.instance_variable_get(:@klass)
    end

    test "#associated_table keeps association table name when names match" do
      table_metadata = TableMetadata.new(Developer, Developer.arel_table)

      associated_table_metadata = table_metadata.associated_table("audit_logs")
      symbol_associated_table_metadata = table_metadata.associated_table(:audit_logs)

      assert_equal "audit_logs", associated_table_metadata.arel_table.name
      assert_equal AuditLog, associated_table_metadata.instance_variable_get(:@klass)
      assert_equal :audit_logs, symbol_associated_table_metadata.arel_table.name
      assert_equal AuditLog, symbol_associated_table_metadata.instance_variable_get(:@klass)
    end

    test "#associated_table aliases association tables when names differ" do
      table_metadata = TableMetadata.new(Developer, Developer.arel_table)

      associated_table_metadata = table_metadata.associated_table("required_audit_logs")

      assert_equal "required_audit_logs", associated_table_metadata.arel_table.name
      assert_equal AuditLogRequired, associated_table_metadata.instance_variable_get(:@klass)
    end

    test "#associated_table builds anonymous metadata for polymorphic associations" do
      table_metadata = TableMetadata.new(Tagging, Tagging.arel_table)

      associated_table_metadata = table_metadata.associated_table("taggable")

      assert_equal "taggable", associated_table_metadata.arel_table.name
      assert_nil associated_table_metadata.instance_variable_get(:@klass)
    end

    test "#associated_table can infer association class from block" do
      table_metadata = TableMetadata.new(Developer, Developer.arel_table)

      associated_table_metadata = table_metadata.associated_table("custom_audit_logs") { AuditLog }

      assert_equal "custom_audit_logs", associated_table_metadata.arel_table.name
      assert_equal AuditLog, associated_table_metadata.instance_variable_get(:@klass)
    end

    test "#associated_table builds anonymous metadata for unknown tables" do
      table_metadata = TableMetadata.new(Developer, Developer.arel_table)

      associated_table_metadata = table_metadata.associated_table("unknown_logs")

      assert_equal "unknown_logs", associated_table_metadata.arel_table.name
      assert_nil associated_table_metadata.instance_variable_get(:@klass)
    end
  end
end
