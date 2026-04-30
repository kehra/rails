# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/core_ext/name_error"

class NameErrorTest < ActiveSupport::TestCase
  def test_name_error_should_set_missing_name
    exc = assert_raise NameError do
      SomeNameThatNobodyWillUse____Really ? 1 : 0
    end
    assert_equal "NameErrorTest::SomeNameThatNobodyWillUse____Really", exc.missing_name
    assert exc.missing_name?(:SomeNameThatNobodyWillUse____Really)
    assert exc.missing_name?("NameErrorTest::SomeNameThatNobodyWillUse____Really")
    assert_equal NameErrorTest, exc.receiver
  end

  def test_missing_method_should_ignore_missing_name
    exc = assert_raise NameError do
      some_method_that_does_not_exist
    end
    assert_not exc.missing_name?(:Foo)
    assert_nil exc.missing_name
    assert_equal self, exc.receiver
  end

  def test_top_level_missing_constant_uses_name
    exc = assert_raise NameError do
      ::SomeTopLevelNameThatNobodyWillUse____Really
    end

    assert_equal "SomeTopLevelNameThatNobodyWillUse____Really", exc.missing_name
    assert exc.missing_name?("SomeTopLevelNameThatNobodyWillUse____Really")
    assert_equal Object, exc.receiver
  end

  def test_missing_name_falls_back_to_message_when_receiver_is_unavailable
    exc = NameError.new("uninitialized constant LegacyNamespace::MissingThing")

    assert_equal "LegacyNamespace::MissingThing", exc.missing_name
  end

  def test_missing_name_falls_back_to_message_without_original_message
    exc = NameError.new("uninitialized constant LegacyMissingThing")
    def exc.respond_to?(name, include_private = false)
      name == :original_message ? false : super
    end

    assert_equal "LegacyMissingThing", exc.missing_name
  end

  def test_missing_name_returns_nil_when_message_has_no_constant_name
    exc = NameError.new("uninitialized constant ")

    assert_nil exc.missing_name
  end
end
