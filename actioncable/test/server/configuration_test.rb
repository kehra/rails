# frozen_string_literal: true

require "test_helper"
require "active_support/core_ext/hash/indifferent_access"

class ConfigurationTest < ActionCable::TestCase
  def setup
    @config = ActionCable::Server::Configuration.new
  end

  test "initializes defaults" do
    assert_equal [], @config.log_tags
    assert_equal [], @config.filter_parameters
    assert_equal 4, @config.worker_pool_size
    assert_not @config.disable_request_forgery_protection
    assert @config.allow_same_origin_as_host
    assert_equal ActionCable::Connection::Base, @config.connection_class.call
    assert_equal [ 200, { Rack::CONTENT_TYPE => "text/html", "date" => String }, [] ].first, @config.health_check_application.call({}).first
  end

  test "configuration accessors can be assigned" do
    logger = Logger.new(nil)
    health_check_application = ->(_env) { [ 204, {}, [] ] }
    connection_class = -> { Class.new(ActionCable::Connection::Base) }

    @config.logger = logger
    @config.log_tags = [ :uuid ]
    @config.connection_class = connection_class
    @config.worker_pool_size = 8
    @config.disable_request_forgery_protection = true
    @config.allowed_request_origins = %w[http://example.com]
    @config.allow_same_origin_as_host = false
    @config.filter_parameters = [ :password ]
    @config.cable = { adapter: "async" }.with_indifferent_access
    @config.url = "ws://example.com/cable"
    @config.mount_path = "/cable"
    @config.precompile_assets = false
    @config.health_check_path = "/up"
    @config.health_check_application = health_check_application

    assert_same logger, @config.logger
    assert_equal [ :uuid ], @config.log_tags
    assert_same connection_class, @config.connection_class
    assert_equal 8, @config.worker_pool_size
    assert @config.disable_request_forgery_protection
    assert_equal %w[http://example.com], @config.allowed_request_origins
    assert_not @config.allow_same_origin_as_host
    assert_equal [ :password ], @config.filter_parameters
    assert_equal "async", @config.cable[:adapter]
    assert_equal "ws://example.com/cable", @config.url
    assert_equal "/cable", @config.mount_path
    assert_equal false, @config.precompile_assets
    assert_equal "/up", @config.health_check_path
    assert_same health_check_application, @config.health_check_application
  end

  test "pubsub_adapter constantizes configured adapter" do
    @config.cable = { adapter: "async" }.with_indifferent_access

    assert_equal ActionCable::SubscriptionAdapter::Async, @config.pubsub_adapter
  end

  test "pubsub_adapter special cases postgresql constant name" do
    @config.cable = { adapter: "postgresql" }.with_indifferent_access

    assert_equal ActionCable::SubscriptionAdapter::PostgreSQL, @config.pubsub_adapter
  end

  test "pubsub_adapter reports unknown adapter" do
    @config.cable = { adapter: "not_real" }.with_indifferent_access

    error = assert_raises(LoadError) { @config.pubsub_adapter }
    assert_match "Could not load the 'not_real' Action Cable pubsub adapter", error.message
  end

  test "pubsub_adapter reports dependency load errors" do
    @config.cable = { adapter: "async" }.with_indifferent_access
    @config.define_singleton_method(:require) do |_path|
      error = LoadError.new("missing dependency")
      error.define_singleton_method(:path) { "missing_dependency" }
      raise error
    end

    error = assert_raises(LoadError) { @config.pubsub_adapter }
    assert_match "Error loading the 'async' Action Cable pubsub adapter", error.message
  end
end
