# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch"

class ActionDispatchTest < ActiveSupport::TestCase
  test "test_app accessors read and write shared app" do
    original = ActionDispatch.test_app
    app = ->(env) { [200, {}, [env["PATH_INFO"]]] }
    dispatch = Class.new { include ActionDispatch }.new

    ActionDispatch.test_app = app

    assert_same app, ActionDispatch.test_app

    dispatch.test_app = :instance_app
    assert_equal :instance_app, dispatch.test_app
    assert_equal :instance_app, ActionDispatch.test_app
  ensure
    ActionDispatch.test_app = original
  end

  test "eager_load loads routing after autoloads" do
    loaded = []

    ActionDispatch::Routing.stub(:eager_load!, -> { loaded << :routing }) do
      ActionDispatch.eager_load!
    end

    assert_equal [:routing], loaded
  end
end
