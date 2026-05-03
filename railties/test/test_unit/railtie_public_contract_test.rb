# frozen_string_literal: true

require "abstract_unit"
require "rails/test_unit/railtie"
require "rake"

class RailsTestUnitRailtiePublicContractTest < ActiveSupport::TestCase
  test "configures test unit generators" do
    generators = Rails::TestUnitRailtie.config.app_generators

    assert_equal :test_unit, generators.options[:rails][:test_framework]
    assert_equal({ fixture: true, fixture_replacement: nil }, generators.options[:test_unit])
    assert_equal :test_unit, generators.options[:rails][:integration_tool]
    assert_equal :test_unit, generators.options[:rails][:system_tests]
  end

  test "line filtering initializer extends active support test case on load" do
    initializer = Rails::TestUnitRailtie.initializers.find { |entry| entry.name == "test_unit.line_filtering" }
    assert_not_nil initializer

    with_load_hooks_restored do
      initializer.run
      ActiveSupport.run_load_hooks(:active_support_test_case, ActiveSupport::TestCase)

      assert_respond_to ActiveSupport::TestCase, :run_suite
    end
  end

  test "rake task hook loads testing tasks" do
    railtie = Rails::TestUnitRailtie.instance
    loaded = []

    singleton = class << railtie; self; end
    singleton.define_method(:load) { |path| loaded << path }
    railtie.send(:run_tasks_blocks, nil)

    assert_equal ["rails/test_unit/testing.rake"], loaded
  ensure
    singleton.remove_method(:load) if singleton&.method_defined?(:load)
  end

  private
    def with_load_hooks_restored
      original_hooks = ActiveSupport.instance_variable_get(:@load_hooks).transform_values(&:dup)
      original_loaded = ActiveSupport.instance_variable_get(:@loaded).transform_values(&:dup)
      yield
    ensure
      ActiveSupport.instance_variable_set(:@load_hooks, original_hooks)
      ActiveSupport.instance_variable_set(:@loaded, original_loaded)
    end
end
