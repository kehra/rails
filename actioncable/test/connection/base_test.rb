# frozen_string_literal: true

require "test_helper"
require "stubs/test_server"
require "active_support/core_ext/object/json"

class ActionCable::Connection::BaseTest < ActionCable::TestCase
  class Connection < ActionCable::Connection::Base
    attr_reader :subscriptions, :connected
    # Make this method public so we can test it
    attr_reader :socket

    def connect
      @connected = true
    end

    def disconnect
      @connected = false
    end
  end

  class CommandConnection < Connection
    def run_command(payload)
      handle_channel_command payload
    end
  end

  test "on connection open" do
    connection = open_connection

    assert_called_with(connection.socket, :transmit, [{ type: "welcome" }]) do
      connection.handle_open
    end

    assert connection.connected
  end

  test "on connection close" do
    connection = open_connection

    # Set up the connection
    connection.handle_open
    assert connection.connected

    assert_called(connection.subscriptions, :unsubscribe_from_all) do
      connection.handle_close
    end

    assert_not connection.connected
  end

  test "connection exposes server dependencies and request state" do
    connection = open_connection

    assert_same connection.socket.env, connection.env
    assert_same connection.socket.request, connection.request
    assert_nil connection.protocol
    assert_respond_to connection.socket, :perform_work
    assert_instance_of ActionCable::Connection::Subscriptions, connection.subscriptions
    assert_respond_to connection.logger, :info
  end

  test "connection statistics" do
    connection = open_connection
    connection.handle_open

    statistics = connection.statistics

    assert_predicate statistics[:identifier], :blank?
    assert_kind_of Time, statistics[:started_at]
    assert_equal [], statistics[:subscriptions]
    assert_nil statistics[:request_id]
  end

  test "beat transmits ping" do
    connection = open_connection

    assert_called(connection.socket, :transmit) do
      connection.beat
    end
  end

  test "handle channel command runs command callbacks" do
    connection = CommandConnection.new(TestServer.new, socket)
    payload = { "command" => "ping" }

    assert_called_with(connection.subscriptions, :execute_command, [payload]) do
      connection.run_command payload
    end
  end

  test "explicitly closing a connection" do
    connection = open_connection

    assert_called(connection.socket, :close) do
      assert_called(connection.socket, :transmit, [{ type: "disconnect", reason: "testing", reconnect: true }]) do
        connection.close(reason: "testing")
      end
    end
  end

  test "inspect does not show internals" do
    connection = open_connection
    assert_match(/\A#<ActionCable::Connection::BaseTest::Connection:0x[0-9a-f]+>\z/, connection.inspect)
  end

  test "socket is closed even when transmit raises during close" do
    connection = open_connection
    socket = connection.socket

    # Simulate a socket whose output queue has already been closed (e.g. after a
    # prior restart call), so that transmitting the disconnect message raises.
    socket.stub(:transmit, ->(*) { raise ClosedQueueError, "queue closed" }) do
      assert_called(socket, :close) do
        connection.close(reason: "server_restart")
      end
    end
  end

  test "#broadcast" do
    connection = Connection.new(ActionCable.server, ActionCable::Server::Socket.new(ActionCable.server, {}))

    messages = capture_broadcasts("test") do
      connection.broadcast("test", { message: "hello" })
    end

    assert_equal 1, messages.size
    assert_equal({ "message" => "hello" }, messages.first)
  end

  private
    def open_connection
      server = TestServer.new
      env = Rack::MockRequest.env_for "/test", "HTTP_CONNECTION" => "upgrade", "HTTP_UPGRADE" => "websocket",
        "HTTP_HOST" => "localhost", "HTTP_ORIGIN" => "http://rubyonrails.com"

      Connection.new(server, socket(server, env))
    end

    def socket(server = TestServer.new, env = nil)
      env ||= Rack::MockRequest.env_for "/test", "HTTP_CONNECTION" => "upgrade", "HTTP_UPGRADE" => "websocket",
        "HTTP_HOST" => "localhost", "HTTP_ORIGIN" => "http://rubyonrails.com"

      ActionCable::Server::Socket.new(server, env)
    end
end
