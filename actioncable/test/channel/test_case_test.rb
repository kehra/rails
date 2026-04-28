# frozen_string_literal: true

require "test_helper"

class TestTestChannel < ActionCable::Channel::Base
end

class NonInferrableExplicitClassChannelTest < ActionCable::Channel::TestCase
  tests TestTestChannel

  def test_set_channel_class_manual
    assert_equal TestTestChannel, self.class.channel_class
  end

  def test_channel_class_accessor
    original_channel_class = self.class._channel_class

    self.class._channel_class = TestTestChannel

    assert_equal TestTestChannel, self.class._channel_class
  ensure
    self.class._channel_class = original_channel_class
  end
end

class NonInferrableSymbolNameChannelTest < ActionCable::Channel::TestCase
  tests :test_test_channel

  def test_set_channel_class_manual_using_symbol
    assert_equal TestTestChannel, self.class.channel_class
  end
end

class NonInferrableStringNameChannelTest < ActionCable::Channel::TestCase
  tests "test_test_channel"

  def test_set_channel_class_manual_using_string
    assert_equal TestTestChannel, self.class.channel_class
  end
end

class NonInferrableChannelTest < ActionCable::Channel::TestCase
  def test_tests_rejects_unknown_channel_argument
    error = assert_raises(ActionCable::Channel::NonInferrableChannelError) do
      self.class.tests(Object.new)
    end

    assert_match "Unable to determine the channel to test", error.message
  end

  def test_default_channel_inference_error
    original_channel_class = self.class._channel_class
    self.class._channel_class = nil

    error = assert_raises(ActionCable::Channel::NonInferrableChannelError) do
      self.class.channel_class
    end

    assert_match self.class.name, error.message
  ensure
    self.class._channel_class = original_channel_class
  end
end

class SubscriptionsTestChannel < ActionCable::Channel::Base
end

class SubscriptionsTestChannelTest < ActionCable::Channel::TestCase
  def setup
    stub_connection
  end

  def test_no_subscribe
    assert_nil subscription
  end

  def test_subscribe
    subscribe

    assert_predicate subscription, :confirmed?
    assert_not subscription.rejected?
    assert_equal 1, connection.transmissions.size
    assert_equal ActionCable::INTERNAL[:message_types][:confirmation],
                 connection.transmissions.last["type"]
  end
end

class StubConnectionTest < ActionCable::Channel::TestCase
  tests SubscriptionsTestChannel

  GIDIdentifier = Struct.new(:id) do
    def to_gid_param
      "gid://test/User/#{id}"
    end
  end

  def test_connection_identifiers
    stub_connection username: "John", admin: true

    subscribe

    assert_equal "John", subscription.username
    assert subscription.admin
    assert_equal "John:true", connection.connection_identifier
  end

  def test_connection_stub_exposes_server_state_and_transmits_with_indifferent_access
    stub_connection user: GIDIdentifier.new(7), token: "abc"

    connection.transmit("type" => "ping")

    assert_same ActionCable.server, connection.server
    assert_same ActionCable.server.config, connection.config
    assert_same ActionCable.server.pubsub, connection.pubsub
    assert_instance_of ActionCable::Connection::Subscriptions, connection.subscriptions
    assert_respond_to connection.logger, :tagged
    assert_equal [ :user, :token ], connection.identifiers
    assert_equal "ping", connection.transmissions.last[:type]
    assert_equal "abc:gid://test/User/7", connection.connection_identifier
    assert_same connection.connection_identifier, connection.connection_identifier
  end

  def test_connection_identifier_ignores_nil_identifier_names
    stub_connection
    connection.instance_variable_set(:@identifiers, [ nil ])

    assert_equal "", connection.connection_identifier
  end
end

class RejectionTestChannel < ActionCable::Channel::Base
  def subscribed
    reject
  end
end

class RejectionTestChannelTest < ActionCable::Channel::TestCase
  def test_rejection
    subscribe

    assert_not subscription.confirmed?
    assert_predicate subscription, :rejected?
    assert_equal 1, connection.transmissions.size
    assert_equal ActionCable::INTERNAL[:message_types][:rejection],
                 connection.transmissions.last["type"]
  end

  def test_perform_when_rejected
    subscribe

    assert_raises(RuntimeError, "Must be subscribed!") do
      perform :anything
    end
  end
end

class StreamsTestChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "test_#{params[:id] || 0}"
  end

  def unsubscribed
    stop_stream_from "test_#{params[:id] || 0}"
  end
end

class StreamsTestChannelTest < ActionCable::Channel::TestCase
  def test_stream_without_params
    subscribe

    assert_has_stream "test_0"
  end

  def test_stream_with_params
    subscribe id: 42

    assert_has_stream "test_42"
  end

  def test_not_stream_without_params
    subscribe
    unsubscribe

    assert_has_no_stream "test_0"
  end

  def test_not_stream_with_params
    subscribe id: 42
    perform :unsubscribed, id: 42

    assert_has_no_stream "test_42"
  end

  def test_unsubscribe_from_stream
    subscribe
    unsubscribe

    assert_no_streams
  end

  def test_channel_stub_periodic_timer_methods_are_no_ops
    subscribe

    assert_nil subscription.start_periodic_timers
    assert_nil subscription.stop_periodic_timers
  end
end

class StreamsForTestChannel < ActionCable::Channel::Base
  def subscribed
    stream_for User.new(params[:id])
  end

  def unsubscribed
    stop_stream_for User.new(params[:id])
  end
end

class StreamsForTestChannelTest < ActionCable::Channel::TestCase
  def test_stream_with_params
    subscribe id: 42

    assert_has_stream_for User.new(42)
  end

  def test_not_stream_with_params
    subscribe id: 42
    perform :unsubscribed, id: 42

    assert_has_no_stream_for User.new(42)
  end

  def test_not_stream_for_different_object
    subscribe id: 42

    assert_has_no_stream_for User.new(43)
  end
end

class NoStreamsTestChannel < ActionCable::Channel::Base
  def subscribed; end # no-op
end

class NoStreamsTestChannelTest < ActionCable::Channel::TestCase
  def test_stream_with_params
    subscribe

    assert_no_streams
  end
end

class PerformTestChannel < ActionCable::Channel::Base
  def echo(data)
    data.delete("action")
    transmit data
  end

  def ping
    transmit({ type: "pong" })
  end
end

class PerformTestChannelTest < ActionCable::Channel::TestCase
  def setup
    stub_connection user_id: 2016
    subscribe id: 5
  end

  def test_perform_with_params
    perform :echo, text: "You are man!"

    assert_equal({ "text" => "You are man!" }, transmissions.last)
  end

  def test_perform_and_transmit
    perform :ping

    assert_equal "pong", transmissions.last["type"]
  end
end

class PerformUnsubscribedTestChannelTest < ActionCable::Channel::TestCase
  tests PerformTestChannel

  def test_perform_when_unsubscribed
    assert_raises do
      perform :echo
    end
  end
end

class BroadcastsTestChannel < ActionCable::Channel::Base
  def broadcast(data)
    ActionCable.server.broadcast(
      "broadcast_#{params[:id]}",
      { text: data["message"], user_id: user_id }
    )
  end

  def broadcast_to_user(data)
    user = User.new user_id

    broadcast_to user, text: data["message"]
  end
end

class BroadcastsTestChannelTest < ActionCable::Channel::TestCase
  def setup
    stub_connection user_id: 2017
    subscribe id: 5
  end

  def test_broadcast_matchers_included
    assert_broadcast_on("broadcast_5", user_id: 2017, text: "SOS") do
      perform :broadcast, message: "SOS"
    end
  end

  def test_broadcast_to_object
    user = User.new(2017)

    assert_broadcasts(user, 1) do
      perform :broadcast_to_user, text: "SOS"
    end
  end

  def test_broadcast_to_object_with_data
    user = User.new(2017)

    assert_broadcast_on(user, text: "SOS") do
      perform :broadcast_to_user, message: "SOS"
    end
  end
end
