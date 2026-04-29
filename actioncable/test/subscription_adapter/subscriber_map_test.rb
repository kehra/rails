# frozen_string_literal: true

require "test_helper"

class SubscriberMapTest < ActionCable::TestCase
  class RecordingSubscriberMap < ActionCable::SubscriptionAdapter::SubscriberMap
    attr_reader :added_channels, :removed_channels, :callbacks

    def initialize
      super
      @added_channels = []
      @removed_channels = []
      @callbacks = []
    end

    def add_channel(channel, on_success)
      @added_channels << channel
      super
    end

    def remove_channel(channel)
      @removed_channels << channel
    end

    def invoke_callback(callback, message)
      @callbacks << [ callback, message ]
      super
    end
  end

  test "broadcast should not change subscribers" do
    setup_subscription_map
    origin = @subscription_map.instance_variable_get(:@subscribers).dup

    @subscription_map.broadcast("not_exist_channel", "")

    assert_equal origin, @subscription_map.instance_variable_get(:@subscribers)
  end

  test "add_subscriber adds a new channel and calls success callback" do
    setup_subscription_map
    called = false

    @subscription_map.add_subscriber("room", -> {}, -> { called = true })

    assert called
    assert_equal [ "room" ], @subscription_map.added_channels
  end

  test "add_subscriber calls success callback for existing channel" do
    setup_subscription_map
    @subscription_map.add_subscriber("room", -> {}, nil)
    called = false

    @subscription_map.add_subscriber("room", -> {}, -> { called = true })

    assert called
    assert_equal [ "room" ], @subscription_map.added_channels
  end

  test "broadcast invokes callbacks for subscribers" do
    setup_subscription_map
    received = []
    subscriber = -> message { received << message }
    @subscription_map.add_subscriber("room", subscriber, nil)

    @subscription_map.broadcast("room", "hello")

    assert_equal [ "hello" ], received
    assert_equal [[ subscriber, "hello" ]], @subscription_map.callbacks
  end

  test "remove_subscriber removes channel when last subscriber is removed" do
    setup_subscription_map
    subscriber = -> {}
    @subscription_map.add_subscriber("room", subscriber, nil)

    @subscription_map.remove_subscriber("room", subscriber)

    assert_equal [ "room" ], @subscription_map.removed_channels
    assert_not @subscription_map.instance_variable_get(:@subscribers).key?("room")
  end

  test "remove_subscriber keeps channel while subscribers remain" do
    setup_subscription_map
    first = -> {}
    second = -> {}
    @subscription_map.add_subscriber("room", first, nil)
    @subscription_map.add_subscriber("room", second, nil)

    @subscription_map.remove_subscriber("room", first)

    assert_empty @subscription_map.removed_channels
    assert_equal [ second ], @subscription_map.instance_variable_get(:@subscribers)["room"]
  end

  test "default remove_channel is a no-op" do
    subscription_map = ActionCable::SubscriptionAdapter::SubscriberMap.new

    assert_nil subscription_map.remove_channel("room")
  end

  private
    def setup_subscription_map
      @subscription_map = RecordingSubscriberMap.new
    end
end
