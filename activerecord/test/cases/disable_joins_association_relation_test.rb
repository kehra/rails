# frozen_string_literal: true

require "cases/helper"
require "active_record/disable_joins_association_relation"
require "models/member"

class DisableJoinsAssociationRelationTest < ActiveRecord::TestCase
  def test_first_with_limit_delegates_to_loaded_records_limit
    relation = ActiveRecord::DisableJoinsAssociationRelation.new(Member, "id", [1])
    records = Class.new do
      attr_reader :limit_value

      def limit(value)
        @limit_value = value
        self
      end

      def first
        [:first, limit_value]
      end
    end.new
    relation.define_singleton_method(:records) { records }

    assert_equal [:first, 2], relation.first(2)
  end
end
