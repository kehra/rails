# frozen_string_literal: true

require "abstract_unit"
require "rails/test_unit/reporter"
require "minitest/mock"

class TestUnitReporterTest < ActiveSupport::TestCase
  class ExampleTest < Minitest::Test
    def woot; end
  end

  setup do
    @output = StringIO.new
    @reporter = Rails::TestUnitReporter.new @output, output_inline: true
    @old_app_root = Rails::TestUnitReporter.app_root
    Rails::TestUnitReporter.app_root = File.expand_path("../../", __dir__)
  end

  teardown do
    Rails::TestUnitReporter.app_root = @old_app_root
  end

  test "prints rerun snippet to run a single failed test" do
    record(failed_test)
    @reporter.report

    assert_match %r{^#{test_run_command_regex} .*test/test_unit/reporter_test\.rb:\d+$}, @output.string
    assert_rerun_snippet_count 1
  end

  test "prints rerun snippet for every failed test" do
    record(failed_test)
    record(failed_test)
    record(failed_test)
    @reporter.report

    assert_rerun_snippet_count 3
  end

  test "does not print snippet for successful and skipped tests" do
    record(passing_test)
    record(skipped_test)
    @reporter.report
    assert_no_match "Failed tests:", @output.string
    assert_rerun_snippet_count 0
  end

  test "prints rerun snippet for skipped tests if run in verbose mode" do
    @reporter = Rails::TestUnitReporter.new @output, verbose: true
    record(skipped_test)
    @reporter.report

    assert_rerun_snippet_count 1
  end

  test "allows to customize the executable in the rerun snippet" do
    original_executable = Rails::TestUnitReporter.executable
    begin
      Rails::TestUnitReporter.executable = "bin/test"
      record(failed_test)
      @reporter.report

      assert_match %r{^bin/test .*test/test_unit/reporter_test\.rb:\d+$}, @output.string
    ensure
      Rails::TestUnitReporter.executable = original_executable
    end
  end

  test "outputs failures inline" do
    record(failed_test)
    @reporter.report

    expect = %r{\AF\n\nFailure:\nTestUnitReporterTest::ExampleTest#woot \[[^\]]+\]:\nboo\n\n#{test_run_command_regex} test/test_unit/reporter_test\.rb:\d+\n\n\z}
    assert_match expect, @output.string
  end

  test "outputs errors inline" do
    record(errored_test)
    @reporter.report

    expect = %r{\AE\n\nError:\nTestUnitReporterTest::ExampleTest#woot:\nArgumentError: wups\n    some_test.rb:4\n\n#{test_run_command_regex} .*test/test_unit/reporter_test\.rb:\d+\n\n\z}
    assert_match expect, @output.string
  end

  test "outputs skipped tests inline if verbose" do
    @reporter = Rails::TestUnitReporter.new @output, verbose: true, output_inline: true
    record(skipped_test)
    @reporter.report

    expect = %r{\ATestUnitReporterTest::ExampleTest#woot = 10\.00 s = S\n\n\nSkipped:\nTestUnitReporterTest::ExampleTest#woot \[[^\]]+\]:\nskipchurches, misstemples\n\n#{test_run_command_regex} test/test_unit/reporter_test\.rb:\d+\n\n\z}
    assert_match expect, @output.string
  end

  test "does not output rerun snippets after run" do
    record(failed_test)
    @reporter.report

    assert_no_match "Failed tests:", @output.string
  end

  test "fail fast interrupts run on failure" do
    @reporter = Rails::TestUnitReporter.new @output, fail_fast: true
    interrupt_raised = false

    # Minitest passes through Interrupt, catch it manually.
    begin
      record(failed_test)
    rescue Interrupt
      interrupt_raised = true
    ensure
      assert interrupt_raised, "Expected Interrupt to be raised."
    end
  end

  test "fail fast interrupts run on error" do
    @reporter = Rails::TestUnitReporter.new @output, fail_fast: true
    interrupt_raised = false

    # Minitest passes through Interrupt, catch it manually.
    begin
      record(errored_test)
    rescue Interrupt
      interrupt_raised = true
    ensure
      assert interrupt_raised, "Expected Interrupt to be raised."
    end
  end

  test "fail fast does not interrupt run skips" do
    @reporter = Rails::TestUnitReporter.new @output, fail_fast: true

    record(skipped_test)
    assert_no_match "Failed tests:", @output.string
  end

  test "outputs colored passing results" do
    @output.stub(:tty?, true) do
      @reporter = Rails::TestUnitReporter.new @output, color: true, output_inline: true
      record(passing_test)

      expect = %r{\e\[32m\.\e\[0m}
      assert_match expect, @output.string
    end
  end

  test "outputs colored skipped results" do
    @output.stub(:tty?, true) do
      @reporter = Rails::TestUnitReporter.new @output, color: true, output_inline: true
      record(skipped_test)

      expect = %r{\e\[33mS\e\[0m}
      assert_match expect, @output.string
    end
  end

  test "outputs colored failed results" do
    @output.stub(:tty?, true) do
      @reporter = Rails::TestUnitReporter.new @output, color: true, output_inline: true
      record(failed_test)

      expected = %r{\e\[31mF\e\[0m\n\n\e\[31mFailure:\nTestUnitReporterTest::ExampleTest#woot \[test/test_unit/reporter_test.rb:\d+\]:\nboo\n\e\[0m\n\n#{test_run_command_regex} .*test/test_unit/reporter_test.rb:\d+\n\n}
      assert_match expected, @output.string
    end
  end

  test "deferred report prints failed tests and filters skips outside verbose mode" do
    @reporter = Rails::TestUnitReporter.new @output, output_inline: false
    record(failed_test)
    record(skipped_test)

    assert_equal 1, @reporter.filtered_results.size
    assert_match %r{\A#{test_run_command_regex} test/test_unit/reporter_test\.rb:\d+\z}, @reporter.aggregated_results

    @reporter.report
    assert_match(/Failed tests:/, @output.string)
    assert_rerun_snippet_count 1
  end

  test "relative path returns original file when app root is unavailable" do
    @reporter.define_singleton_method(:app_root) { nil }

    assert_equal "tmp/example_test.rb", @reporter.relative_path_for("tmp/example_test.rb")
  end

  test "rerun snippet falls back to method source location" do
    result = SourceLocationOnlyResult.new
    @reporter.results << result

    assert_match %r{#{test_run_command_regex} .*test/test_unit/reporter_test\.rb:\d+}, @reporter.aggregated_results
  end

  test "app root defaults from env engine rails root and current directory" do
    original_app_root = Rails::TestUnitReporter.app_root
    Rails::TestUnitReporter.app_root = nil

    Dir.mktmpdir do |dir|
      with_env("RAILS_TEST_PWD" => dir) do
        reporter = Rails::TestUnitReporter.new(StringIO.new)
        assert_equal "test/example_test.rb", reporter.relative_path_for(File.join(dir, "test/example_test.rb"))
      end

      with_engine_root(dir) do
        reporter = Rails::TestUnitReporter.new(StringIO.new)
        assert_equal "test/example_test.rb", reporter.relative_path_for(File.join(dir, "test/example_test.rb"))
      end

      with_env("RAILS_TEST_PWD" => nil) do
        Rails.stub(:root, Pathname.new(dir)) do
          reporter = Rails::TestUnitReporter.new(StringIO.new)
          assert_equal "test/example_test.rb", reporter.relative_path_for(File.join(dir, "test/example_test.rb"))
        end
      end

      without_rails_root_response do
        reporter = Rails::TestUnitReporter.new(StringIO.new)
        assert_equal "test/example_test.rb", reporter.relative_path_for(File.join(Dir.pwd, "test/example_test.rb"))
      end
    end
  ensure
    Rails::TestUnitReporter.app_root = original_app_root
  end

  test "outputs colored error results" do
    @output.stub(:tty?, true) do
      @reporter = Rails::TestUnitReporter.new @output, color: true, output_inline: true
      record(errored_test)

      expected = %r{\e\[31mE\e\[0m\n\n\e\[31mError:\nTestUnitReporterTest::ExampleTest#woot:\nArgumentError: wups\n    some_test.rb:4\n\e\[0m}
      assert_match expected, @output.string
    end
  end

  class SourceLocationOnlyResult
    attr_reader :name, :time

    def initialize
      @name = :woot
      @time = 0.0
    end

    def woot; end
    def result_code = "F"
    def failure = true
    def skipped? = false
  end

  private
    def record(test_result)
      @reporter.prerecord(test_result.klass.constantize, test_result.name)
      @reporter.record(test_result)
    end

    def assert_rerun_snippet_count(snippet_count)
      assert_equal snippet_count, @output.string.scan(%r{^#{test_run_command_regex} }).size
    end

    def failed_test
      ft = Minitest::Result.from(ExampleTest.new(:woot))
      ft.failures << begin
                       flunk("boo")
                     rescue Minitest::Assertion => e
                       e
                     end
      ft
    end

    def errored_test
      error = ArgumentError.new("wups")
      error.set_backtrace([ "some_test.rb:4" ])

      et = Minitest::Result.from(ExampleTest.new(:woot))
      et.failures << Minitest::UnexpectedError.new(error)
      et
    end

    def passing_test
      Minitest::Result.from(ExampleTest.new(:woot))
    end

    def skipped_test
      st = Minitest::Result.from(ExampleTest.new(:woot))
      st.failures << begin
                       raise Minitest::Skip, "skipchurches, misstemples"
                     rescue Minitest::Assertion => e
                       e
                     end
      st.time = 10
      st
    end

    def with_env(values)
      old_values = values.keys.to_h { |key| [key, ENV[key]] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      values.each_key { |key| ENV[key] = old_values[key] }
    end

    def with_engine_root(path)
      had_constant = Object.const_defined?(:ENGINE_ROOT)
      original = Object.const_get(:ENGINE_ROOT) if had_constant
      Object.send(:remove_const, :ENGINE_ROOT) if had_constant
      Object.const_set(:ENGINE_ROOT, path)
      yield
    ensure
      Object.send(:remove_const, :ENGINE_ROOT) if Object.const_defined?(:ENGINE_ROOT)
      Object.const_set(:ENGINE_ROOT, original) if had_constant
    end

    def without_rails_root_response
      singleton = class << Rails; self; end
      original = Rails.method(:respond_to?)
      singleton.define_method(:respond_to?) do |name, include_private = false|
        name == :root ? false : original.call(name, include_private)
      end
      yield
    ensure
      singleton.define_method(:respond_to?) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def test_run_command_regex
      %r{bin/rails test|bin/test}
    end
end
