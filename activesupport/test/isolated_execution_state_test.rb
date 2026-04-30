# frozen_string_literal: true

require_relative "abstract_unit"

class IsolatedExecutionStateTest < ActiveSupport::TestCase
  setup do
    ActiveSupport::IsolatedExecutionState.clear
    @original_isolation_level = ActiveSupport::IsolatedExecutionState.isolation_level
  end

  teardown do
    ActiveSupport::IsolatedExecutionState.clear
    ActiveSupport::IsolatedExecutionState.isolation_level = @original_isolation_level
  end

  test "#[] when isolation level is :fiber" do
    ActiveSupport::IsolatedExecutionState.isolation_level = :fiber

    ActiveSupport::IsolatedExecutionState[:test] = 42
    assert_equal 42, ActiveSupport::IsolatedExecutionState[:test]
    enumerator = Enumerator.new do |yielder|
      yielder.yield ActiveSupport::IsolatedExecutionState[:test]
    end
    assert_nil enumerator.next

    assert_nil Thread.new { ActiveSupport::IsolatedExecutionState[:test] }.value
  end

  test "#[] when isolation level is :thread" do
    ActiveSupport::IsolatedExecutionState.isolation_level = :thread

    ActiveSupport::IsolatedExecutionState[:test] = 42
    assert_equal 42, ActiveSupport::IsolatedExecutionState[:test]
    enumerator = Enumerator.new do |yielder|
      yielder.yield ActiveSupport::IsolatedExecutionState[:test]
    end
    assert_equal 42, enumerator.next

    assert_nil Thread.new { ActiveSupport::IsolatedExecutionState[:test] }.value
  end

  test "changing the isolation level clear the old store" do
    original = ActiveSupport::IsolatedExecutionState.isolation_level
    other = ActiveSupport::IsolatedExecutionState.isolation_level == :fiber ? :thread : :fiber

    ActiveSupport::IsolatedExecutionState[:test] = 42
    ActiveSupport::IsolatedExecutionState.isolation_level = original
    assert_equal 42, ActiveSupport::IsolatedExecutionState[:test]

    ActiveSupport::IsolatedExecutionState.isolation_level = other
    assert_nil ActiveSupport::IsolatedExecutionState[:test]

    ActiveSupport::IsolatedExecutionState.isolation_level = original
    assert_nil ActiveSupport::IsolatedExecutionState[:test]
  end

  test "#share_with copies state from another thread" do
    ActiveSupport::IsolatedExecutionState[:foo] = "bar"
    ActiveSupport::IsolatedExecutionState[:baz] = "qux"

    t1 = Thread.current
    result = nil

    Thread.new do
      ActiveSupport::IsolatedExecutionState.share_with(t1) do
        result = {
          foo: ActiveSupport::IsolatedExecutionState[:foo],
          baz: ActiveSupport::IsolatedExecutionState[:baz]
        }
      end
    end.join

    assert_equal "bar", result[:foo]
    assert_equal "qux", result[:baz]
  end

  test "#share_with restores original state after block" do
    ActiveSupport::IsolatedExecutionState[:original] = "value"

    t1 = Thread.current
    ActiveSupport::IsolatedExecutionState[:foo] = "parent"

    Thread.new do
      ActiveSupport::IsolatedExecutionState[:foo] = "child"
      ActiveSupport::IsolatedExecutionState[:bar] = "child_only"

      ActiveSupport::IsolatedExecutionState.share_with(t1) do
        assert_equal "parent", ActiveSupport::IsolatedExecutionState[:foo]
        assert_nil ActiveSupport::IsolatedExecutionState[:bar]
      end

      # After block, child thread should have its original state back
      assert_equal "child", ActiveSupport::IsolatedExecutionState[:foo]
      assert_equal "child_only", ActiveSupport::IsolatedExecutionState[:bar]
    end.join
  end

  test "#share_with with except parameter accepts single key or array" do
    ActiveSupport::IsolatedExecutionState[:foo] = "bar"
    ActiveSupport::IsolatedExecutionState[:secret1] = "should not copy"
    ActiveSupport::IsolatedExecutionState[:secret2] = "also should not copy"
    ActiveSupport::IsolatedExecutionState[:keep] = "keep this"

    t1 = Thread.current
    result = nil

    Thread.new do
      ActiveSupport::IsolatedExecutionState.share_with(t1, except: [:secret1, :secret2]) do
        result = {
          foo: ActiveSupport::IsolatedExecutionState[:foo],
          secret1: ActiveSupport::IsolatedExecutionState[:secret1],
          secret2: ActiveSupport::IsolatedExecutionState[:secret2],
          keep: ActiveSupport::IsolatedExecutionState[:keep]
        }
      end
    end.join

    assert_equal "bar", result[:foo]
    assert_nil result[:secret1]
    assert_nil result[:secret2]
    assert_equal "keep this", result[:keep]
  end

  test "invalid isolation level raises" do
    error = assert_raises(ArgumentError) do
      ActiveSupport::IsolatedExecutionState.isolation_level = :process
    end

    assert_equal "isolation_level must be `:thread` or `:fiber`, got: `:process`", error.message
  end

  test "key delete and clear handle absent and present state" do
    Thread.current.active_support_execution_state = nil
    assert_nil ActiveSupport::IsolatedExecutionState.key?(:test)
    assert_nil ActiveSupport::IsolatedExecutionState.delete(:test)
    assert_nil ActiveSupport::IsolatedExecutionState.clear

    ActiveSupport::IsolatedExecutionState[:test] = 42
    assert ActiveSupport::IsolatedExecutionState.key?(:test)
    assert_equal 42, ActiveSupport::IsolatedExecutionState.delete(:test)
    assert_not ActiveSupport::IsolatedExecutionState.key?(:test)

    ActiveSupport::IsolatedExecutionState[:test] = 42
    ActiveSupport::IsolatedExecutionState.clear
    assert_not ActiveSupport::IsolatedExecutionState.key?(:test)
  end

  test "share_with without source state runs with nil state and restores old state" do
    other = Thread.new { Thread.current }.value
    ActiveSupport::IsolatedExecutionState[:existing] = "value"

    ActiveSupport::IsolatedExecutionState.share_with(other) do
      assert_nil ActiveSupport::IsolatedExecutionState[:existing]
      ActiveSupport::IsolatedExecutionState[:temporary] = "inside"
    end

    assert_equal "value", ActiveSupport::IsolatedExecutionState[:existing]
    assert_nil ActiveSupport::IsolatedExecutionState[:temporary]
  end

  test "isolation level case fallback is harmless for validated custom level" do
    silence_warnings do
      Array.class_eval do
        alias_method :__isolated_execution_state_original_include?, :include?
        def include?(object)
          (self == [:thread, :fiber] && object == :custom) || __isolated_execution_state_original_include?(object)
        end
      end
    end

    ActiveSupport::IsolatedExecutionState.isolation_level = :custom

    assert_nil ActiveSupport::IsolatedExecutionState.scope
    assert_equal :custom, ActiveSupport::IsolatedExecutionState.isolation_level
  ensure
    ActiveSupport::IsolatedExecutionState.instance_variable_set(:@isolation_level, nil)
    ActiveSupport::IsolatedExecutionState.isolation_level = @original_isolation_level
    if Array.method_defined?(:__isolated_execution_state_original_include?)
      silence_warnings do
        Array.class_eval do
          alias_method :include?, :__isolated_execution_state_original_include?
          remove_method :__isolated_execution_state_original_include?
        end
      end
    end
  end
end
