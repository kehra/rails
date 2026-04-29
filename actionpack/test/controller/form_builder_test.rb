# frozen_string_literal: true

require "abstract_unit"

class FormBuilderController < ActionController::Base
  class SpecializedFormBuilder < ActionView::Helpers::FormBuilder ; end

  default_form_builder SpecializedFormBuilder
end

class ControllerFormBuilderTest < ActiveSupport::TestCase
  setup do
    @controller = FormBuilderController.new
  end

  def test_default_form_builder_assigned
    assert_equal FormBuilderController::SpecializedFormBuilder, @controller.default_form_builder
  end

  def test_default_form_builder_class_attribute_accessors
    original_builder = FormBuilderController._default_form_builder
    FormBuilderController._default_form_builder = ActionView::Helpers::FormBuilder

    assert_equal ActionView::Helpers::FormBuilder, FormBuilderController._default_form_builder
    assert_equal ActionView::Helpers::FormBuilder, @controller.default_form_builder
  ensure
    FormBuilderController._default_form_builder = original_builder
  end
end
