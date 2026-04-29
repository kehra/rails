# frozen_string_literal: true

require "test_helper"
require "stubs/test_server"
require "action_view"

class ActionCableHelperTest < ActionCable::TestCase
  class ViewContext
    include ActionView::Helpers::TagHelper
    include ActionCable::Helpers::ActionCableHelper
  end

  setup do
    @old_server = ActionCable.instance_variable_get(:@server)
    @server = TestServer.new
    ActionCable.instance_variable_set(:@server, @server)
  end

  teardown do
    ActionCable.instance_variable_set(:@server, @old_server)
  end

  test "action_cable_meta_tag uses configured url" do
    @server.config.url = "ws://example.test/cable"
    @server.config.mount_path = "/cable"

    assert_equal '<meta name="action-cable-url" content="ws://example.test/cable" />', ViewContext.new.action_cable_meta_tag
  end

  test "action_cable_meta_tag falls back to configured mount path" do
    @server.config.url = nil
    @server.config.mount_path = "/cable"

    assert_equal '<meta name="action-cable-url" content="/cable" />', ViewContext.new.action_cable_meta_tag
  end

  test "action_cable_meta_tag raises when no url is configured" do
    @server.config.url = nil
    @server.config.mount_path = nil

    error = assert_raises(RuntimeError) { ViewContext.new.action_cable_meta_tag }
    assert_equal "No Action Cable URL configured -- please configure this at config.action_cable.url", error.message
  end
end
