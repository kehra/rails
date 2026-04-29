# frozen_string_literal: true

require "abstract_unit"

class ActionControllerAPIModulesTest < ActiveSupport::TestCase
  class ApiRenderingController < ActionController::API
    attr_reader :processed_options

    def _process_options(options)
      @processed_options = options
      options[:processed] = true
    end
  end

  def test_without_modules_excludes_modules_by_symbol_and_constant
    modules = ActionController::API.without_modules(:UrlFor, ActionController::StrongParameters)

    assert_not_includes modules, ActionController::UrlFor
    assert_not_includes modules, ActionController::StrongParameters
    assert_includes modules, ActionController::ApiRendering
  end

  def test_api_rendering_processes_options_before_delegating
    controller = ApiRenderingController.new
    options = { body: "hello" }

    assert_equal "hello", controller.render_to_body(options)
    assert_equal({ body: "hello", processed: true }, controller.processed_options)
  end
end
