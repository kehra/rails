# frozen_string_literal: true

require "test_helper"
require "stubs/test_connection"

class ActionCable::Channel::CallbacksTest < ActionCable::TestCase
  class CallbackChannel < ActionCable::Channel::Base
    before_subscribe { record_callback(:before_subscribe) }
    after_subscribe { record_callback(:after_subscribe) }
    on_subscribe { record_callback(:on_subscribe) }

    before_unsubscribe { record_callback(:before_unsubscribe) }
    after_unsubscribe { record_callback(:after_unsubscribe) }
    on_unsubscribe { record_callback(:on_unsubscribe) }

    attr_reader :callbacks

    def initialize(*)
      @callbacks = []
      super
    end

    def subscribed
      record_callback(:subscribed)
    end

    def unsubscribed
      record_callback(:unsubscribed)
    end

    private
      def record_callback(name)
        @callbacks << name
      end
  end

  setup do
    @channel = CallbackChannel.new(TestConnection.new, "{id: 1}")
  end

  test "subscribe callbacks run around subscribed hook" do
    @channel.subscribe_to_channel

    assert_equal [ :before_subscribe, :subscribed, :on_subscribe, :after_subscribe ], @channel.callbacks
  end

  test "unsubscribe callbacks run around unsubscribed hook" do
    @channel.unsubscribe_from_channel

    assert_equal [ :before_unsubscribe, :unsubscribed, :on_unsubscribe, :after_unsubscribe ], @channel.callbacks
  end
end
