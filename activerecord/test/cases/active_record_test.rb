# frozen_string_literal: true

require "cases/helper"

class ActiveRecordTest < ActiveRecord::TestCase
  self.use_transactional_tests = false

  Warning = Struct.new(:message, :code)

  teardown do
    ActiveRecord.db_warnings_action = :ignore
    ActiveRecord.default_timezone = :utc
    ActiveRecord.marshalling_format_version = 6.1
    ActiveRecord.permanent_connection_checkout = true
  end

  test ".permanent_connection_checkout= accepts supported modes" do
    ActiveRecord.permanent_connection_checkout = true
    assert_equal true, ActiveRecord.permanent_connection_checkout

    ActiveRecord.permanent_connection_checkout = :deprecated
    assert_equal :deprecated, ActiveRecord.permanent_connection_checkout

    ActiveRecord.permanent_connection_checkout = :disallowed
    assert_equal :disallowed, ActiveRecord.permanent_connection_checkout
  end

  test ".permanent_connection_checkout= rejects unsupported modes" do
    error = assert_raises(ArgumentError) do
      ActiveRecord.permanent_connection_checkout = false
    end

    assert_equal "permanent_connection_checkout must be one of: `true`, `:deprecated` or `:disallowed`", error.message
  end

  test ".marshalling_format_version delegates to marshalling configuration" do
    assert_equal 6.1, ActiveRecord.marshalling_format_version

    ActiveRecord.marshalling_format_version = 7.1
    assert_equal 7.1, ActiveRecord.marshalling_format_version

    ActiveRecord.marshalling_format_version = 6.1
    assert_equal 6.1, ActiveRecord.marshalling_format_version
  end

  test ".default_timezone= accepts utc and local" do
    ActiveRecord.default_timezone = :local
    assert_equal :local, ActiveRecord.default_timezone

    ActiveRecord.default_timezone = :utc
    assert_equal :utc, ActiveRecord.default_timezone
  end

  test ".default_timezone= rejects unsupported values" do
    error = assert_raises(ArgumentError) do
      ActiveRecord.default_timezone = :tokyo
    end

    assert_equal "default_timezone must be either :utc (default) or :local.", error.message
  end

  test ".db_warnings_action= maps ignore to no action" do
    ActiveRecord.db_warnings_action = :ignore

    assert_nil ActiveRecord.db_warnings_action
  end

  test ".db_warnings_action= logs warning class message and optional code" do
    messages = []
    logger = Class.new do
      define_method(:initialize) { |messages| @messages = messages }
      define_method(:warn) { |message| @messages << message }
    end.new(messages)

    ActiveRecord::Base.stub(:logger, logger) do
      ActiveRecord.db_warnings_action = :log
      ActiveRecord.db_warnings_action.call(Warning.new("query warning", "01000"))
      ActiveRecord.db_warnings_action.call(Warning.new("query note", nil))
    end

    assert_equal [
      "[ActiveRecordTest::Warning] query warning (01000)",
      "[ActiveRecordTest::Warning] query note",
    ], messages
  end

  test ".db_warnings_action= raises warnings" do
    ActiveRecord.db_warnings_action = :raise
    warning = StandardError.new("database warning")

    assert_same warning, assert_raises(StandardError) { ActiveRecord.db_warnings_action.call(warning) }
  end

  test ".db_warnings_action= reports warnings as handled errors" do
    reports = []
    error_reporter = Class.new do
      define_method(:initialize) { |reports| @reports = reports }
      define_method(:report) { |warning, handled:| @reports << [warning, handled] }
    end.new(reports)
    warning = Warning.new("reported warning", nil)

    original_error = Rails.method(:error) if Rails.respond_to?(:error)
    Rails.define_singleton_method(:error) { error_reporter }

    ActiveRecord.db_warnings_action = :report
    ActiveRecord.db_warnings_action.call(warning)

    assert_equal [[warning, true]], reports
  ensure
    Rails.singleton_class.remove_method(:error)
    Rails.define_singleton_method(:error, original_error) if original_error
  end

  test ".db_warnings_action= accepts custom procs" do
    called_with = []
    action = ->(warning) { called_with << warning }
    warning = Warning.new("custom warning", nil)

    ActiveRecord.db_warnings_action = action
    ActiveRecord.db_warnings_action.call(warning)

    assert_same action, ActiveRecord.db_warnings_action
    assert_equal [warning], called_with
  end

  test ".db_warnings_action= rejects unknown actions" do
    error = assert_raises(ArgumentError) do
      ActiveRecord.db_warnings_action = :unknown
    end

    assert_equal "db_warnings_action must be one of :ignore, :log, :raise, :report, or a custom proc.", error.message
  end

  test ".disconnect_all! delegates to pool configs" do
    called = false

    ActiveRecord::ConnectionAdapters::PoolConfig.stub(:disconnect_all!, -> { called = true }) do
      ActiveRecord.disconnect_all!
    end

    assert called
  end

  test ".eager_load! eager loads nested Active Record namespaces" do
    eager_loaded = []
    namespaces = [
      ActiveRecord::Locking,
      ActiveRecord::Scoping,
      ActiveRecord::Associations,
      ActiveRecord::AttributeMethods,
      ActiveRecord::ConnectionAdapters,
      ActiveRecord::Encryption,
    ]

    stub = lambda do |remaining|
      namespace = remaining.first
      if namespace
        namespace.stub(:eager_load!, -> { eager_loaded << namespace }) do
          stub.call(remaining.drop(1))
        end
      else
        ActiveRecord.eager_load!
      end
    end

    stub.call(namespaces)

    assert_equal namespaces, eager_loaded.last(namespaces.size)
  end

  unless in_memory_db?
    test ".disconnect_all! closes all connections" do
      ActiveRecord::Base.lease_connection.connect!
      assert_predicate ActiveRecord::Base, :connected?

      ActiveRecord.disconnect_all!
      assert_not_predicate ActiveRecord::Base, :connected?

      ActiveRecord::Base.lease_connection.connect!
      assert_predicate ActiveRecord::Base, :connected?
    end
  end
end
