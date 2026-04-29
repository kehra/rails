# frozen_string_literal: true

require "abstract_unit"
require "action_view/helpers"

class ActionViewHelpersTest < ActiveSupport::TestCase
  test "eager load also eager loads tag helpers" do
    called = false
    original = ActionView::Helpers::Tags.method(:eager_load!)

    silence_warnings do
      ActionView::Helpers::Tags.define_singleton_method(:eager_load!) do
        called = true
        original.call
      end
    end

    ActionView::Helpers.eager_load!
    assert called
  ensure
    silence_warnings do
      ActionView::Helpers::Tags.define_singleton_method(:eager_load!, original) if original
    end
  end
end
