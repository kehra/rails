# frozen_string_literal: true

require "test_helper"
require "stubs/test_server"
require "active_support/core_ext/hash/indifferent_access"

class BaseTest < ActionCable::TestCase
  def setup
    @server = ActionCable::Server::Base.new
    @server.config.cable = { adapter: "async" }.with_indifferent_access
  end

  class FakeConnection
    def close(**)
    end

    def disconnect
    end
  end

  class TestConnection < ActionCable::Connection::Base
    identified_by :current_user

    def self.call
      self
    end
  end

  test "#restart closes all open connections" do
    conn = FakeConnection.new
    @server.add_connection(conn)

    assert_called(conn, :close) do
      @server.restart
    end
  end

  test "#restart shuts down worker pool" do
    assert_called(@server.worker_pool, :halt) do
      @server.restart
    end
  end

  test "class config accessor and logger delegate to config" do
    original_config = ActionCable::Server::Base.config
    config = ActionCable::Server::Configuration.new
    logger = ActiveSupport::Logger.new(StringIO.new)
    config.logger = logger

    ActionCable::Server::Base.config = config

    assert_same config, ActionCable::Server::Base.config
    assert_same logger, ActionCable::Server::Base.logger
  ensure
    ActionCable::Server::Base.config = original_config
  end

  test "initializes with config and exposes dependencies" do
    assert_same @server.config, @server.config
    assert_same @server.config.logger, @server.logger
    assert_instance_of Monitor, @server.mutex
    assert_instance_of ActionCable::RemoteConnections, @server.remote_connections
    assert_instance_of ActionCable::Server::StreamEventLoop, @server.event_loop
    assert_instance_of ActionCable::Server::Worker, @server.worker_pool
    assert_instance_of ActionCable::SubscriptionAdapter::Async, @server.pubsub
  end

  test "call delegates health check path to health check application" do
    @server.config.health_check_path = "/up"
    @server.config.health_check_application = ->(_env) { [ 204, {}, [] ] }

    assert_equal [ 204, {}, [] ], @server.call("PATH_INFO" => "/up")
  end

  test "call builds configured connection" do
    @server.config.connection_class = -> { TestConnection }
    @server.config.disable_request_forgery_protection = true

    env = Rack::MockRequest.env_for "/cable", "HTTP_CONNECTION" => "upgrade", "HTTP_UPGRADE" => "websocket"

    assert_equal [ -1, {}, [] ], @server.call(env)
  end

  test "disconnect delegates to remote connections" do
    identifiers = { current_user: "david" }

    assert_called_with(@server.remote_connections, :where, [identifiers], returns: FakeConnection.new) do
      @server.disconnect identifiers
    end
  end

  test "connection identifiers come from configured connection class" do
    @server.config.connection_class = -> { TestConnection }

    assert_equal Set[:current_user], @server.connection_identifiers
  end

  test "#restart shuts down pub/sub adapter" do
    assert_called(@server.pubsub, :shutdown) do
      @server.restart
    end
  end
end
