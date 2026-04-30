# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/execution_context/test_helper"
require "active_support/core_ext/object/with"

class ExecutionContextTest < ActiveSupport::TestCase
  # ExecutionContext is automatically reset in Rails app via executor hooks set in railtie
  # But not in Active Support's own test suite.
  include ActiveSupport::ExecutionContext::TestHelper

  test "#set restore the modified keys when the block exits" do
    assert_nil ActiveSupport::ExecutionContext.to_h[:foo]
    ActiveSupport::ExecutionContext.set(foo: "bar") do
      assert_equal "bar", ActiveSupport::ExecutionContext.to_h[:foo]
      ActiveSupport::ExecutionContext.set(foo: "plop") do
        assert_equal "plop", ActiveSupport::ExecutionContext.to_h[:foo]
      end
      assert_equal "bar", ActiveSupport::ExecutionContext.to_h[:foo]

      ActiveSupport::ExecutionContext[:direct_assignment] = "present"
      ActiveSupport::ExecutionContext.set(multi_assignment: "present")
    end

    assert_nil ActiveSupport::ExecutionContext.to_h[:foo]

    assert_equal "present", ActiveSupport::ExecutionContext.to_h[:direct_assignment]
    assert_equal "present", ActiveSupport::ExecutionContext.to_h[:multi_assignment]
  end

  test "#pop after #flush does not corrupt execution context" do
    ActiveSupport::ExecutionContext.with(nestable: true) do
      # simulate executor hooks from active_support/railtie.rb
      executor = Class.new(ActiveSupport::Executor)

      executor.to_run do
        ActiveSupport::ExecutionContext.push
      end
      executor.to_complete do
        ActiveSupport::ExecutionContext.pop
      end
      executor.wrap do
        # simulate app.reloader.before_class_unload hooks from active_support/railtie.rb
        ActiveSupport::ExecutionContext.flush
      end

      assert_equal({}, ActiveSupport::ExecutionContext.to_h)
    end
  end

  test "#set coerce keys to symbol" do
    ActiveSupport::ExecutionContext.set("foo" => "bar") do
      assert_equal "bar", ActiveSupport::ExecutionContext.to_h[:foo]
    end
  end

  test "#[]= coerce keys to symbol" do
    ActiveSupport::ExecutionContext["symbol_key"] = "symbolized"
    assert_equal "symbolized", ActiveSupport::ExecutionContext.to_h[:symbol_key]
  end

  test "#to_h returns a copy of the context" do
    ActiveSupport::ExecutionContext[:foo] = 42
    context = ActiveSupport::ExecutionContext.to_h
    context[:foo] = 43
    assert_equal 42, ActiveSupport::ExecutionContext.to_h[:foo]
  end

  test "after_change callback runs on assignments and set blocks" do
    callbacks = ActiveSupport::ExecutionContext.instance_variable_get(:@after_change_callbacks)
    calls = 0
    callback = -> { calls += 1 }
    ActiveSupport::ExecutionContext.after_change(&callback)

    ActiveSupport::ExecutionContext[:foo] = "bar"
    ActiveSupport::ExecutionContext.set(foo: "baz") { }

    assert_equal 3, calls
  ensure
    callbacks&.delete(callback)
  end

  test "push and pop clear context when not nestable" do
    ActiveSupport::ExecutionContext[:foo] = "bar"
    assert_same ActiveSupport::ExecutionContext, ActiveSupport::ExecutionContext.push
    assert_empty ActiveSupport::ExecutionContext.to_h

    ActiveSupport::ExecutionContext[:foo] = "baz"
    assert_same ActiveSupport::ExecutionContext, ActiveSupport::ExecutionContext.pop
    assert_empty ActiveSupport::ExecutionContext.to_h
  end

  test "current_attributes_instances returns the active record store" do
    ActiveSupport::ExecutionContext.current_attributes_instances[:current] = "value"

    assert_equal({ current: "value" }, ActiveSupport::ExecutionContext.current_attributes_instances)
  end
end
