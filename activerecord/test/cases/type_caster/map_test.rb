# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module TypeCaster
    class MapTest < ActiveSupport::TestCase
      test "type_for_attribute delegates to model class" do
        klass = Class.new do
          def self.type_for_attribute(name)
            { "name" => ActiveRecord::Type::String.new }.fetch(name.to_s)
          end
        end
        type_caster = Map.new(klass)

        assert_instance_of ActiveRecord::Type::String, type_caster.type_for_attribute(:name)
      end

      test "type_cast_for_database serializes with the attribute type" do
        type = Class.new(ActiveModel::Type::Value) do
          def serialize(value)
            "serialized #{value}"
          end
        end.new
        klass = Class.new do
          define_singleton_method(:type_for_attribute) { |_name| type }
        end
        type_caster = Map.new(klass)

        assert_equal "serialized value", type_caster.type_cast_for_database(:name, "value")
      end

      test "type caster namespace is defined" do
        assert_kind_of Module, ActiveRecord::TypeCaster
      end
    end
  end
end
