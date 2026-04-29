# frozen_string_literal: true

require "active_support/testing/autorun"
require "action_view/railtie"

class ActionViewRailtieTest < ActiveSupport::TestCase
  test "railtie registers action view defaults and namespace" do
    config = ActionView::Railtie.config

    assert_nil config.action_view.embed_authenticity_token_in_remote_forms
    assert_equal true, config.action_view.debug_missing_translation
    assert_equal true, config.action_view.apply_stylesheet_media_default
    assert_equal false, config.action_view.prepend_content_exfiltration_prevention
    assert_includes config.eager_load_namespaces, ActionView
  end

  test "deprecator initializer exposes action view deprecator" do
    app = Class.new do
      attr_reader :deprecators

      def initialize
        @deprecators = {}
      end
    end.new

    initializer = ActionView::Railtie.initializers.find { |entry| entry.name == "action_view.deprecator" }
    assert_not_nil initializer

    initializer.run(app)
    assert_same ActionView.deprecator, app.deprecators[:action_view]
  end
end
