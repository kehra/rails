# frozen_string_literal: true

require "test_helper"

class ActionCableTest < ActionCable::TestCase
  test ".server memoizes a server instance" do
    old_server = ActionCable.instance_variable_get(:@server)
    ActionCable.remove_instance_variable(:@server) if ActionCable.instance_variable_defined?(:@server)

    server = ActionCable.server

    assert_instance_of ActionCable::Server::Base, server
    assert_same server, ActionCable.server
  ensure
    ActionCable.instance_variable_set(:@server, old_server)
  end

  test "configuration is available through the public top-level constant" do
    assert_same ActionCable::Configuration, ActionCable::Server::Configuration
    assert_instance_of ActionCable::Configuration, ActionCable::Server::Base.config
    assert_instance_of ActionCable::Configuration, ActionCable::Server::Base.new.config
  end

  test ".gem_version returns the loaded version as a Gem::Version" do
    assert_equal Gem::Version.new(ActionCable::VERSION::STRING), ActionCable.gem_version
  end

  test ".version delegates to .gem_version" do
    assert_equal ActionCable.gem_version, ActionCable.version
  end
end
