# frozen_string_literal: true

require_relative "../abstract_unit"

class ErrorReporterAssertionsTest < ActiveSupport::TestCase
  test "assert_error_reported returns matching report" do
    error = ArgumentError.new("boom")

    report = assert_error_reported(ArgumentError) do
      ActiveSupport.error_reporter.report(error, handled: false, severity: :error, context: { section: "checkout" }, source: "test")
    end

    assert_same error, report.error
    assert_equal false, report.handled?
    assert_equal :error, report.severity
    assert_equal({ section: "checkout" }, report.context)
    assert_equal "test", report.source
  end

  test "assert_error_reported fails when no errors are reported" do
    error = assert_raises(Minitest::Assertion) do
      assert_error_reported(ArgumentError) do
        # no-op
      end
    end

    assert_equal "Expected a ArgumentError to be reported, but there were no errors reported.", error.message
  end

  test "assert_error_reported fails when reports do not match class" do
    error = assert_raises(Minitest::Assertion) do
      assert_error_reported(ArgumentError) do
        ActiveSupport.error_reporter.report(RuntimeError.new("boom"))
      end
    end

    assert_includes error.message, "Expected a ArgumentError to be reported"
    assert_includes error.message, "RuntimeError"
  end

  test "assert_no_error_reported passes and fails" do
    assert_no_error_reported do
      # no-op
    end

    error = assert_raises(Minitest::Assertion) do
      assert_no_error_reported do
        ActiveSupport.error_reporter.report(RuntimeError.new("boom"))
      end
    end

    assert_match(/Expected \[.*\] to be empty/, error.message)
  end

  test "capture_error_reports filters reports by class" do
    reports = capture_error_reports(ArgumentError) do
      ActiveSupport.error_reporter.report(ArgumentError.new("one"))
      ActiveSupport.error_reporter.report(RuntimeError.new("two"))
      ActiveSupport.error_reporter.report(ArgumentError.new("three"))
    end

    assert_equal ["one", "three"], reports.map { |report| report.error.message }
  end

  test "error collector records nested reports and removes recorder" do
    reports = ActiveSupport::Testing::ErrorReporterAssertions::ErrorCollector.record do
      ActiveSupport.error_reporter.report(RuntimeError.new("outer"))
      nested = ActiveSupport::Testing::ErrorReporterAssertions::ErrorCollector.record do
        ActiveSupport.error_reporter.report(RuntimeError.new("inner"))
      end
      assert_equal ["inner"], nested.map { |report| report.error.message }
    end

    assert_equal ["outer", "inner"], reports.map { |report| report.error.message }
    assert_empty ActiveSupport::IsolatedExecutionState[:active_support_error_reporter_assertions]
  end

  test "error collector report succeeds without active recorder" do
    ActiveSupport::IsolatedExecutionState[:active_support_error_reporter_assertions] = nil

    assert_equal true, ActiveSupport::Testing::ErrorReporterAssertions::ErrorCollector.report(RuntimeError.new("ignored"), handled: true, severity: :warning, context: {}, source: "test")
  end

  test "error collector handles concurrent subscribe" do
    collector = ActiveSupport::Testing::ErrorReporterAssertions::ErrorCollector
    original_subscribed = collector.instance_variable_get(:@subscribed)
    original_mutex = collector.instance_variable_get(:@mutex)
    collector.instance_variable_set(:@subscribed, false)
    collector.instance_variable_set(:@mutex, Object.new.tap do |mutex|
      mutex.define_singleton_method(:synchronize) do |&block|
        collector.instance_variable_set(:@subscribed, true)
        block.call
      end
    end)

    assert_equal [], collector.record { }
  ensure
    collector.instance_variable_set(:@mutex, original_mutex)
    collector.instance_variable_set(:@subscribed, original_subscribed)
  end

  test "error collector requires configured reporter" do
    original_reporter = ActiveSupport.error_reporter
    collector = ActiveSupport::Testing::ErrorReporterAssertions::ErrorCollector
    original_subscribed = collector.instance_variable_get(:@subscribed)
    collector.instance_variable_set(:@subscribed, false)
    ActiveSupport.error_reporter = nil

    error = assert_raises(Minitest::Assertion) do
      collector.record { }
    end
    assert_equal "No error reporter is configured", error.message
  ensure
    ActiveSupport.error_reporter = original_reporter
    collector.instance_variable_set(:@subscribed, original_subscribed)
  end
end
