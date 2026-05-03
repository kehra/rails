# frozen_string_literal: true

require "abstract_unit"
require "rails/test_unit/line_filtering"

class RailsTestUnitLineFilteringPublicContractTest < ActiveSupport::TestCase
  test "extends minitest 5 run hook and composes filter option" do
    runnable = Class.new do
      class << self
        attr_reader :received_reporter, :received_options
      end
    end
    runnable.singleton_class.include(Module.new do
      def run(reporter, options = {})
        @received_reporter = reporter
        @received_options = options
        :ran
      end
    end)

    with_minitest_version("5.20.0") do
      test_case = self
      compose_filter = ->(target, filter, original) do
        next original.call(target, filter) unless target.equal?(runnable)

        test_case.assert_equal "original", filter
        "composed"
      end

      with_compose_filter(compose_filter) do
        runnable.extend Rails::LineFiltering
        assert_equal :ran, runnable.run(:reporter, filter: "original", untouched: true)
      end
    end

    assert_equal :reporter, runnable.received_reporter
    assert_equal({ filter: "composed", untouched: true }, runnable.received_options)
  end

  test "extends minitest 6 run suite hook and composes include option" do
    runnable = Class.new do
      class << self
        attr_reader :received_reporter, :received_options
      end
    end
    runnable.singleton_class.include(Module.new do
      def run_suite(reporter, options = {})
        @received_reporter = reporter
        @received_options = options
        :ran_suite
      end
    end)

    with_minitest_version("6.0.0") do
      test_case = self
      compose_filter = ->(target, filter, original) do
        next original.call(target, filter) unless target.equal?(runnable)

        test_case.assert_equal "included", filter
        "composed-include"
      end

      with_compose_filter(compose_filter) do
        runnable.extend Rails::LineFiltering
        assert_equal :ran_suite, runnable.run_suite(:reporter, include: "included", untouched: true)
      end
    end

    assert_equal :reporter, runnable.received_reporter
    assert_equal({ include: "composed-include", untouched: true }, runnable.received_options)
  end

  test "leaves unsupported minitest versions without run hooks" do
    runnable = Class.new

    with_minitest_version("7.0.0") do
      runnable.extend Rails::LineFiltering
    end

    assert_raises(NoMethodError) { runnable.run(:reporter) }
    assert_raises(NoMethodError) { runnable.run_suite(:reporter) }
  end

  private
    def with_minitest_version(version)
      original = Minitest.const_get(:VERSION)
      Minitest.send(:remove_const, :VERSION)
      Minitest.const_set(:VERSION, version)
      yield
    ensure
      Minitest.send(:remove_const, :VERSION)
      Minitest.const_set(:VERSION, original)
    end

    def with_compose_filter(implementation)
      singleton = class << Rails::TestUnit::Runner; self; end
      original = Rails::TestUnit::Runner.method(:compose_filter)
      singleton.define_method(:compose_filter) { |runnable, filter| implementation.call(runnable, filter, original) }
      yield
    ensure
      singleton.define_method(:compose_filter) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
