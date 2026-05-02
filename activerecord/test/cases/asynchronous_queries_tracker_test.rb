# frozen_string_literal: true

require "cases/helper"
require "active_record/asynchronous_queries_tracker"

class AsynchronousQueriesTrackerTest < ActiveRecord::TestCase
  def test_current_session_requires_active_query_session
    tracker = ActiveRecord::AsynchronousQueriesTracker.new

    error = assert_raises(ActiveRecord::ActiveRecordError) do
      tracker.current_session
    end

    assert_equal "Can't perform asynchronous queries without a query session", error.message
  end

  def test_start_and_finalize_session_manage_current_session
    tracker = ActiveRecord::AsynchronousQueriesTracker.new

    tracker.start_session
    session = tracker.current_session

    assert_predicate session, :active?
    assert_same tracker, tracker.finalize_session
    assert_not_predicate session, :active?

    error = assert_raises(ActiveRecord::ActiveRecordError) do
      tracker.current_session
    end
    assert_equal "Can't perform asynchronous queries without a query session", error.message
  end

  def test_finalize_session_without_session_is_noop
    tracker = ActiveRecord::AsynchronousQueriesTracker.new

    assert_same tracker, tracker.finalize_session
  end

  def test_session_synchronize_runs_while_active_and_waits_on_finalize
    tracker = ActiveRecord::AsynchronousQueriesTracker.new
    tracker.start_session
    session = tracker.current_session
    ran = false

    session.synchronize do
      ran = true
      assert_predicate session, :active?
    end

    tracker.finalize_session(true)

    assert ran
    assert_not_predicate session, :active?
  end

  def test_executor_hook_contract_runs_and_completes_tracker_sessions
    tracker = ActiveRecord::AsynchronousQueriesTracker.new
    original_tracker = ActiveSupport::IsolatedExecutionState[:active_record_asynchronous_queries_tracker]
    ActiveSupport::IsolatedExecutionState[:active_record_asynchronous_queries_tracker] = tracker

    yielded_tracker = ActiveRecord::AsynchronousQueriesTracker.run

    assert_same tracker, yielded_tracker
    assert_predicate tracker.current_session, :active?
    assert_same tracker, ActiveRecord::AsynchronousQueriesTracker.complete(yielded_tracker)
    assert_raises(ActiveRecord::ActiveRecordError) { tracker.current_session }
  ensure
    ActiveSupport::IsolatedExecutionState[:active_record_asynchronous_queries_tracker] = original_tracker
  end

  def test_install_executor_hooks_registers_tracker
    executor = Class.new do
      class << self
        attr_reader :registered_hook

        def register_hook(hook)
          @registered_hook = hook
        end
      end
    end

    ActiveRecord::AsynchronousQueriesTracker.install_executor_hooks(executor)

    assert_same ActiveRecord::AsynchronousQueriesTracker, executor.registered_hook
  end
end
