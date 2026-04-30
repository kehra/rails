# frozen_string_literal: true

require "cases/helper"

class AttributeAssignmentUnitTest < ActiveRecord::TestCase
  class AssignmentTarget
    include ActiveRecord::AttributeAssignment

    attr_reader :assigned
    attr_accessor :started_on

    def initialize
      @assigned = []
    end

    def assign(attributes)
      _assign_attributes(attributes)
    end

    def _assign_attribute(key, value)
      assigned << [key, value]
    end

    def bad_value=(value)
      raise ArgumentError, "invalid #{value.inspect}"
    end
  end

  def test_assign_attributes_defers_nested_hashes_until_after_scalar_attributes
    target = AssignmentTarget.new

    target.assign(name: "Alice", settings: { theme: "dark" }, active: true)

    assert_equal [["name", "Alice"], ["active", true], ["settings", { theme: "dark" }]], target.assigned
  end

  def test_assign_attributes_handles_scalar_only_and_nested_only_inputs
    scalar_target = AssignmentTarget.new
    scalar_target.assign(name: "Alice")
    assert_equal [["name", "Alice"]], scalar_target.assigned

    nested_target = AssignmentTarget.new
    nested_target.assign(settings: { theme: "dark" })
    assert_equal [["settings", { theme: "dark" }]], nested_target.assigned
  end

  def test_multiparameter_helpers_typecast_positions_and_nil_all_empty_values
    target = AssignmentTarget.new
    callstack = target.send(:extract_callstack_for_multiparameter_attributes, {
      "started_on(2i)" => "5",
      "started_on(1i)" => "2026",
      "started_on(3f)" => "1.5"
    })

    assert_equal({ "started_on" => { 2 => 5, 1 => 2026, 3 => 1.5 } }, callstack)

    target.send(:execute_callstack_for_multiparameter_attributes, {
      "started_on" => { 1 => nil, 2 => nil, 3 => nil }
    })
    assert_nil target.started_on
  end

  def test_multiparameter_assignment_wraps_assignment_errors
    target = AssignmentTarget.new

    error = assert_raises(ActiveRecord::MultiparameterAssignmentErrors) do
      target.send(:execute_callstack_for_multiparameter_attributes, {
        "bad_value" => { 1 => "nope" }
      })
    end

    assert_equal 1, error.errors.size
    assert_instance_of ActiveRecord::AttributeAssignmentError, error.errors.first
    assert_equal "bad_value", error.errors.first.attribute
    assert_includes error.message, "1 error(s) on assignment of multiparameter attributes"
  end
end
