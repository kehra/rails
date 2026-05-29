# frozen_string_literal: true

require "test_helper"
require "stubs/test_socket"

class ActionCable::Channel::NamingTest < ActionCable::TestCase
  class ChatChannel < ActionCable::Channel::Base
  end

  test "channel_name" do
    assert_equal "action_cable:channel:naming_test:chat", ChatChannel.channel_name
  end

  test "channel instance uses class channel_name" do
    channel = ChatChannel.new(TestSocket.new, "{id: 1}")

    assert_equal "action_cable:channel:naming_test:chat", channel.channel_name
  end
end
