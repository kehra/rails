# frozen_string_literal: true

require "abstract_unit"

class ControllerHelperTest < ActionView::TestCase
  tests ActionView::Helpers::ControllerHelper

  ControllerHelperOnly = Class.new do
    include ActionView::Helpers::ControllerHelper
  end

  class SpecializedFormBuilder < ActionView::Helpers::FormBuilder ; end

  def test_assign_controller_sets_default_form_builder
    @controller = Struct.new(:default_form_builder).new(SpecializedFormBuilder)
    assign_controller(@controller)

    assert_equal SpecializedFormBuilder, default_form_builder
  end

  def test_assign_controller_skips_default_form_builder
    @controller = Object.new
    assign_controller(@controller)

    assert_nil default_form_builder
  end

  def test_assign_controller_copies_request_config_and_handles_nil_controller
    request = Object.new
    config = ActiveSupport::InheritableOptions.new(answer: 42)
    controller = Struct.new(:request, :config).new(request, config)

    assign_controller(controller)
    assert_same request, @_request
    assert_equal 42, @_config.answer
    assert_not_same config, @_config

    assign_controller(nil)
    assert_nil @_controller
    assert_same request, @_request
    assert_instance_of ActiveSupport::InheritableOptions, @_config
    assert_nil default_form_builder
  end

  def test_logger_delegates_to_controller_when_present
    logger = Object.new
    @controller = Struct.new(:logger).new(logger)
    assign_controller(@controller)

    assert_same logger, self.logger
  end

  def test_logger_returns_nil_without_controller
    helper = ControllerHelperOnly.new
    helper.assign_controller(nil)

    assert_nil helper.logger
  end

  def test_respond_to
    @controller = Object.new
    assign_controller(@controller)
    assert_not respond_to?(:params)
    assert respond_to?(:assign_controller)

    def @controller.params
      {}
    end
    assert respond_to?(:params)
    assert respond_to?(:assign_controller)
  end
end
