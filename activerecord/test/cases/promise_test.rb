# frozen_string_literal: true

require "cases/helper"
require "active_record/promise"

class PromiseTest < ActiveRecord::TestCase
  FakeFutureResult = Struct.new(:result_value, :pending_value, :canceled_value, keyword_init: true) do
    attr_reader :result_calls

    def initialize(**)
      super
      @result_calls = 0
    end

    def pending? = pending_value
    def canceled? = canceled_value

    def result
      @result_calls += 1
      result_value
    end
  end

  def test_pending_delegates_to_future_result
    future_result = FakeFutureResult.new(result_value: 1, pending_value: true, canceled_value: false)
    promise = ActiveRecord::Promise.new(future_result, nil)

    assert_predicate promise, :pending?
  end

  def test_value_returns_result_and_memoizes_it
    future_result = FakeFutureResult.new(result_value: 3, pending_value: false, canceled_value: false)
    promise = ActiveRecord::Promise.new(future_result, nil)

    assert_equal 3, promise.value
    assert_equal 3, promise.value
    assert_equal 1, future_result.result_calls
  end

  def test_value_applies_block_and_then_composes_blocks
    future_result = FakeFutureResult.new(result_value: 3, pending_value: false, canceled_value: false)
    promise = ActiveRecord::Promise.new(future_result, -> value { value + 1 })

    chained = promise.then { |value| value * 2 }

    assert_equal 8, chained.value
    assert_equal 1, future_result.result_calls
  end

  def test_then_without_existing_block_applies_block_lazily
    future_result = FakeFutureResult.new(result_value: 3, pending_value: false, canceled_value: false)
    promise = ActiveRecord::Promise.new(future_result, nil)

    chained = promise.then { |value| value * 2 }

    assert_equal 6, chained.value
  end

  def test_complete_promise_contract
    promise = ActiveRecord::Promise::Complete.new(3)

    assert_not_predicate promise, :pending?
    assert_equal 3, promise.value
    assert_equal 6, promise.then { |value| value * 2 }.value
  end
end
