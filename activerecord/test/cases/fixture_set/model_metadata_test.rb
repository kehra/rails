# frozen_string_literal: true

require "cases/helper"
require "active_record/fixture_set/model_metadata"

module ActiveRecord
  class FixtureSet
    class ModelMetadataTest < ActiveRecord::TestCase
      FakeColumn = Struct.new(:name)
      FakeType = Struct.new(:type)

      def test_reads_metadata_from_model_class
        metadata = ModelMetadata.new(fake_model_class)

        assert_equal "uuid", metadata.primary_key_name
        assert_equal :uuid, metadata.primary_key_type
        assert_equal :string, metadata.column_type("title")
        assert metadata.has_column?("title")
        assert_not metadata.has_column?("missing")
        assert_equal Set["uuid", "title", "created_at", "updated_at", "type"], metadata.column_names
        assert_equal ["created_at", "updated_at"], metadata.timestamp_column_names
        assert_equal "type", metadata.inheritance_column_name
      end

      def test_caches_column_types
        model_class = fake_model_class
        metadata = ModelMetadata.new(model_class)

        assert_equal :string, metadata.column_type("title")
        assert_equal :string, metadata.column_type("title")
        assert_equal 1, model_class.type_for_attribute_calls.count("title")
      end

      def test_nil_model_class_returns_empty_metadata
        metadata = ModelMetadata.new(nil)

        assert_nil metadata.primary_key_name
        assert_nil metadata.primary_key_type
        assert_nil metadata.column_type("title")
        assert_not metadata.has_column?("title")
        assert_empty metadata.column_names
        assert_nil metadata.inheritance_column_name
      end

      private
        def fake_model_class
          Class.new do
            class << self
              attr_accessor :type_for_attribute_calls
            end

            self.type_for_attribute_calls = []

            def self.primary_key
              "uuid"
            end

            def self.type_for_attribute(column_name)
              type_for_attribute_calls << column_name
              type = column_name == "uuid" ? :uuid : :string
              ActiveRecord::FixtureSet::ModelMetadataTest::FakeType.new(type)
            end

            def self.columns
              %w[uuid title created_at updated_at type].map do |name|
                ActiveRecord::FixtureSet::ModelMetadataTest::FakeColumn.new(name)
              end
            end

            def self.all_timestamp_attributes_in_model
              ["created_at", "updated_at"]
            end

            def self.inheritance_column
              "type"
            end
          end
        end
    end
  end
end
