# frozen_string_literal: true

require "cases/helper"
require "models/developer"

module ActiveRecord
  module TypeCaster
    class ConnectionTest < ActiveSupport::TestCase
      test "#type_for_attribute is not aware of custom types" do
        type_caster = Connection.new(AttributedDeveloper, "developers")

        type = type_caster.type_for_attribute(:name)

        assert_not_equal DeveloperName, type.class
        assert_equal ActiveRecord::Type::String, type.class
      end

      test "#type_cast_for_database serializes with the schema cache column type" do
        schema_cache = Object.new
        schema_cache.define_singleton_method(:data_source_exists?) { |table_name| table_name == "developers" }
        requested_tables = []
        schema_cache.define_singleton_method(:columns_hash) do |table_name|
          requested_tables << table_name
          { "name" => Struct.new(:cast_type).new(ActiveRecord::Type::String.new) }
        end
        klass = Class.new
        klass.define_singleton_method(:schema_cache) { schema_cache }
        type_caster = Connection.new(klass, "developers")

        assert_equal "David", type_caster.type_cast_for_database(:name, :David)
        assert_equal ["developers"], requested_tables
      end

      test "#type_for_attribute falls back to default when table is missing" do
        schema_cache = Object.new
        schema_cache.define_singleton_method(:data_source_exists?) { |table_name| table_name == "other_table" }
        klass = Class.new
        klass.define_singleton_method(:schema_cache) { schema_cache }
        type_caster = Connection.new(klass, "developers")

        assert_same ActiveRecord::Type.default_value, type_caster.type_for_attribute(:name)
      end

      test "#type_for_attribute falls back to default when column is missing" do
        schema_cache = Object.new
        schema_cache.define_singleton_method(:data_source_exists?) { |table_name| table_name == "developers" }
        schema_cache.define_singleton_method(:columns_hash) { |_table_name| {} }
        klass = Class.new
        klass.define_singleton_method(:schema_cache) { schema_cache }
        type_caster = Connection.new(klass, "developers")

        assert_same ActiveRecord::Type.default_value, type_caster.type_for_attribute(:missing)
      end
    end
  end
end
