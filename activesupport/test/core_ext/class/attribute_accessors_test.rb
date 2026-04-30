# frozen_string_literal: true

require_relative "../../abstract_unit"
require "active_support/core_ext/class/attribute_accessors"

class ClassAttributeAccessorsTest < ActiveSupport::TestCase
  test "class attribute accessors entrypoint loads cattr aliases" do
    klass = Class.new do
      cattr_accessor :setting
    end

    klass.setting = "value"
    assert_equal "value", klass.setting
    assert_equal "value", klass.new.setting
  end
end
