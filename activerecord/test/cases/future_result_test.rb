# frozen_string_literal: true

require "cases/helper"
require "active_record/future_result"

class FutureResultTest < ActiveRecord::TestCase
  ResultWithThen = Struct.new(:records) do
    def empty? = records.empty?
    def to_a = records
    def then(&block) = block.call(records)
  end

  FakeIntent = Struct.new(:cast_result_value, :pending_value, :canceled_value, :lock_wait, keyword_init: true) do
    attr_reader :cancel_calls

    def initialize(**)
      super
      @cancel_calls = 0
    end

    def cast_result = cast_result_value
    def pending? = pending_value
    def canceled? = canceled_value
    def cancel = @cancel_calls += 1
  end

  def test_complete_delegates_result_state_and_wraps_then_in_complete_promise
    result = ResultWithThen.new([1, 2])
    complete = ActiveRecord::FutureResult::Complete.new(result)

    assert_equal result, complete.result
    assert_not_predicate complete, :pending?
    assert_not_predicate complete, :canceled?
    assert_not_predicate complete, :empty?
    assert_equal [1, 2], complete.to_a
    assert_equal [2, 4], complete.then { |records| records.map { |record| record * 2 } }.value
  end

  def test_wrap_returns_existing_future_and_complete_results
    complete = ActiveRecord::FutureResult::Complete.new(ResultWithThen.new([]))
    future = ActiveRecord::FutureResult.new(FakeIntent.new(cast_result_value: [], pending_value: true, canceled_value: false, lock_wait: 1))

    assert_same complete, ActiveRecord::FutureResult.wrap(complete)
    assert_same future, ActiveRecord::FutureResult.wrap(future)
  end

  def test_wrap_converts_plain_result_to_complete
    result = ResultWithThen.new([1])

    wrapped = ActiveRecord::FutureResult.wrap(result)

    assert_instance_of ActiveRecord::FutureResult::Complete, wrapped
    assert_same result, wrapped.result
  end

  def test_future_result_delegates_to_intent_and_raises_when_canceled
    result = ResultWithThen.new(["row"])
    intent = FakeIntent.new(cast_result_value: result, pending_value: true, canceled_value: false, lock_wait: 3)
    future = ActiveRecord::FutureResult.new(intent)

    assert_predicate future, :pending?
    assert_not_predicate future, :canceled?
    assert_equal 3, future.lock_wait
    assert_equal ["row"], future.to_a
    assert_equal ["row"], future.result.to_a
    assert_equal ["ROW"], future.then { |records| records.to_a.map(&:upcase) }.value

    future.cancel
    assert_equal 1, intent.cancel_calls

    intent.canceled_value = true
    assert_raises(ActiveRecord::FutureResult::Canceled) { future.result }
  end
end
