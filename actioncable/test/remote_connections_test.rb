# frozen_string_literal: true

require "test_helper"

class ActionCable::RemoteConnectionsTest < ActionCable::TestCase
  class Server
    attr_reader :broadcasts

    def initialize
      @broadcasts = []
    end

    def connection_identifiers
      [ :current_user, :token ]
    end

    def broadcast(channel, payload)
      @broadcasts << [ channel, payload ]
    end
  end

  User = Struct.new(:id) do
    def to_gid_param
      "gid://test/User/#{id}"
    end
  end

  setup do
    @server = Server.new
    @remote_connections = ActionCable::RemoteConnections.new(@server)
  end

  test "stores server" do
    assert_same @server, @remote_connections.server
  end

  test "where returns remote connection for identifiers" do
    remote_connection = @remote_connections.where(current_user: User.new(1), token: "abc")

    assert_instance_of ActionCable::RemoteConnections::RemoteConnection, remote_connection
  end

  test "remote connection disconnect broadcasts to internal channel" do
    remote_connection = @remote_connections.where(current_user: User.new(1), token: "abc")

    remote_connection.disconnect(reconnect: false)

    assert_equal [
      [ "action_cable/abc:gid://test/User/1", { type: "disconnect", reconnect: false } ]
    ], @server.broadcasts
  end

  test "where rejects missing identifiers" do
    assert_raises(ActionCable::RemoteConnections::RemoteConnection::InvalidIdentifiersError) do
      @remote_connections.where(current_user: User.new(1))
    end
  end
end
