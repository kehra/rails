# frozen_string_literal: true

require "test_helper"

class ActionCable::Connection::TaggedLoggerProxyTest < ActionCable::TestCase
  class UntaggedLogger
    attr_reader :messages

    def initialize
      @messages = []
    end

    def info(message = nil)
      @messages << (block_given? ? yield : message)
    end
  end

  test "tags are flattened and can be extended uniquely" do
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(StringIO.new))
    proxy = ActionCable::Connection::TaggedLoggerProxy.new(logger, tags: [ "Cable", [ "User" ] ])

    proxy.add_tags("User", [ "Room" ])

    assert_equal [ "Cable", "User", "Room" ], proxy.tags
  end

  test "tag applies only missing tags to tagged logger" do
    output = StringIO.new
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(output))
    proxy = ActionCable::Connection::TaggedLoggerProxy.new(logger, tags: [ "Cable", "User" ])

    logger.tagged("Cable") do
      proxy.info "connected"
    end

    output.rewind
    assert_includes output.read, "[Cable] [User] connected"
  end

  test "tag yields directly for untagged logger" do
    logger = UntaggedLogger.new
    proxy = ActionCable::Connection::TaggedLoggerProxy.new(logger, tags: [ "Cable" ])

    proxy.info "connected"

    assert_equal [ "connected" ], logger.messages
  end
end
