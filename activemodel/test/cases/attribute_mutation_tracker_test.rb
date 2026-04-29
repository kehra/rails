# frozen_string_literal: true

require "cases/helper"
require "active_model/attribute_mutation_tracker"

module ActiveModel
  class AttributeMutationTrackerTest < ActiveModel::TestCase
    test "tracks changes in an attribute set" do
      attributes = attribute_set(name: "David", age: "40")
      tracker = AttributeMutationTracker.new(attributes)

      assert_not_predicate tracker, :any_changes?
      assert_equal [], tracker.changed_attribute_names
      assert_equal({}, tracker.changed_values)
      assert_equal({}, tracker.changes)
      assert_nil tracker.change_to_attribute(:name)
      assert_not tracker.changed?(:name)
      assert_not tracker.changed_in_place?(:name)

      attributes.write_from_user(:name, "DHH")

      assert_predicate tracker, :any_changes?
      assert_equal [:name], tracker.changed_attribute_names
      assert_equal({ name: "David" }.with_indifferent_access, tracker.changed_values)
      assert_equal({ name: ["David", "DHH"] }.with_indifferent_access, tracker.changes)
      assert_equal ["David", "DHH"], tracker.change_to_attribute(:name)
      assert tracker.changed?(:name, from: "David", to: "DHH")
      assert_not tracker.changed?(:name, from: "Bowie")
      assert_not tracker.changed?(:name, to: "Bowie")

      tracker.forget_change(:name)

      assert_not tracker.changed?(:name)
      assert_equal "DHH", tracker.original_value(:name)
    end

    test "forced changes are tracked until forgotten" do
      attributes = attribute_set(name: "David", age: "40")
      tracker = AttributeMutationTracker.new(attributes)

      tracker.force_change(:age)

      assert tracker.changed?(:age, from: "40", to: "40")
      assert_equal [40, 40], tracker.change_to_attribute(:age)
      assert_equal({ age: 40 }.with_indifferent_access, tracker.changed_values)

      tracker.forget_change(:age)

      assert_not tracker.changed?(:age)
    end

    test "forced mutation tracker snapshots and finalizes forced changes" do
      model = ModelWithAttributes.new
      model.name = ["David"]
      tracker = ForcedMutationTracker.new(model)

      assert_not tracker.changed?(:name)
      assert_equal ["David"], tracker.original_value(:name)
      assert_not tracker.changed_in_place?(:name)

      tracker.force_change(:name)
      model.name << "Heinemeier Hansson"

      assert tracker.changed?(:name, from: ["David"], to: ["David", "Heinemeier Hansson"])
      assert_equal [["David"], ["David", "Heinemeier Hansson"]], tracker.change_to_attribute(:name)

      tracker.force_change(:name)
      assert_equal ["David"], tracker.original_value(:name)

      tracker.finalize_changes
      model.name << "Rails"
      finalized_change = tracker.change_to_attribute(:name)

      assert_equal [["David"], ["David", "Heinemeier Hansson", "Rails"]], finalized_change
      assert_not_same finalized_change, tracker.change_to_attribute(:name)

      tracker.forget_change(:name)
      assert_not tracker.changed?(:name)
      assert_equal finalized_change, tracker.change_to_attribute(:name)
    end

    test "forced mutation tracker keeps non-duplicable values" do
      model = ModelWithAttributes.new
      non_duplicable = Object.new
      def non_duplicable.duplicable? = false
      model.name = non_duplicable
      tracker = ForcedMutationTracker.new(model)

      tracker.force_change(:name)

      assert_same non_duplicable, tracker.original_value(:name)
    end

    test "forced mutation tracker keeps values that fail to clone" do
      model = ModelWithAttributes.new
      unclonable = Object.new
      def unclonable.clone = raise TypeError
      model.name = unclonable
      tracker = ForcedMutationTracker.new(model)

      tracker.force_change(:name)

      assert_same unclonable, tracker.original_value(:name)
    end

    test "null mutation tracker reports no changes" do
      tracker = NullMutationTracker.instance

      assert_equal [], tracker.changed_attribute_names
      assert_equal({}, tracker.changed_values)
      assert_equal({}, tracker.changes)
      assert_nil tracker.change_to_attribute(:name)
      assert_not_predicate tracker, :any_changes?
      assert_not tracker.changed?(:name, from: "David", to: "DHH")
      assert_not tracker.changed_in_place?(:name)
      assert_nil tracker.original_value(:name)
    end

    private
      def attribute_set(values)
        AttributeSet::Builder.new(
          name: Type::String.new,
          age: Type::Integer.new,
        ).build_from_database(values)
      end

      class ModelWithAttributes
        include ActiveModel::Attributes

        attribute :name
      end
  end
end
