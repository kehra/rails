# frozen_string_literal: true

require "test_helper"

class WorkerTest < ActionCable::TestCase
  class Receiver
    attr_accessor :last_action

    def run
      @last_action = :run
    end

    def process(message)
      @last_action = [ :process, message ]
    end

    def connection
      self
    end

    def logger
      # Impersonating a connection requires a TaggedLoggerProxy'ied logger.
      inner_logger = Logger.new(StringIO.new).tap { |l| l.level = Logger::UNKNOWN }
      ActionCable::Connection::TaggedLoggerProxy.new(inner_logger, tags: [])
    end
  end

  setup do
    @worker = ActionCable::Server::Worker.new
    @receiver = Receiver.new
  end

  teardown do
    @receiver.last_action = nil
  end

  test "invoke" do
    @worker.invoke @receiver, :run, connection: @receiver.connection
    assert_equal :run, @receiver.last_action
  end

  test "invoke with arguments" do
    @worker.invoke @receiver, :process, "Hello", connection: @receiver.connection
    assert_equal [ :process, "Hello" ], @receiver.last_action
  end

  test "with_database_connections tags Active Record logger" do
    previous_active_record = Object.const_get(:ActiveRecord) if Object.const_defined?(:ActiveRecord)
    logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new(StringIO.new))

    if previous_active_record
      previous_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = logger
    else
      active_record = Module.new
      base = Class.new
      base.define_singleton_method(:logger) { logger }
      active_record.const_set(:Base, base)
      Object.const_set(:ActiveRecord, active_record)
    end

    @worker.connection = @receiver.connection

    called = false
    @worker.with_database_connections { called = true }

    assert called
  ensure
    @worker.connection = nil

    if defined?(previous_active_record) && previous_active_record
      ActiveRecord::Base.logger = previous_logger
    elsif Object.const_defined?(:ActiveRecord)
      Object.send(:remove_const, :ActiveRecord)
    end
  end
end
