# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class QueryIntentTest < ActiveRecord::TestCase
      class FakeTransaction
        def initialize(joinable: false)
          @joinable = joinable
        end

        def joinable? = @joinable
      end

      class FakeSession
        attr_accessor :active

        def initialize(active: true)
          @active = active
        end

        def active? = @active

        def synchronize
          yield
        end
      end

      class FakePool
        attr_reader :scheduled
        attr_accessor :connection

        def initialize(connection = nil)
          @connection = connection
          @scheduled = []
        end

        def with_connection
          yield connection
        end

        def schedule_query(intent)
          @scheduled << intent
        end
      end

      class FakeAdapter
        attr_accessor :pool, :async_enabled_value, :preventing_writes_value, :transaction,
          :raw_result, :raise_range, :raise_error, :executed_intents, :write_query_result

        def initialize
          @pool = FakePool.new(self)
          @async_enabled_value = false
          @preventing_writes_value = false
          @transaction = FakeTransaction.new
          @raw_result = :raw_result
          @raise_range = false
          @raise_error = nil
          @executed_intents = []
          @write_query_result = false
        end

        def async_enabled? = async_enabled_value
        def preventing_writes? = preventing_writes_value
        def sql_notifications? = true
        def current_transaction = transaction
        def write_query?(sql) = write_query_result || sql.match?(/insert|update|delete/i)
        def type_casted_binds(binds) = binds.map { |bind| "cast-#{bind}" }
        def to_sql_and_binds(_arel, binds, prepare, allow_retry) = ["compiled SQL", binds + [:compiled], !prepare, !allow_retry]
        def cast_result(raw_result) = [:cast, raw_result]
        def affected_rows(_raw_result) = 7

        def execute_intent(intent)
          @executed_intents << intent
          raise @raise_error if @raise_error
          raise ::RangeError if @raise_range

          intent.raw_result = raw_result
        end
      end

      class FakeEvent
        attr_reader :name, :payload, :recorded

        def initialize(name, payload)
          @name = name
          @payload = payload
          @recorded = false
        end

        def record
          @recorded = true
          yield if block_given?
        end
      end

      class FakeInstrumenter
        attr_reader :events

        def initialize
          @events = []
        end

        def new_event(name, payload)
          FakeEvent.new(name, payload).tap { |event| @events << event }
        end
      end

      def test_initialize_requires_query_input_and_exposes_introspection
        error = assert_raises(ArgumentError) do
          QueryIntent.new(adapter: FakeAdapter.new)
        end
        assert_equal "One of arel, raw_sql, or processed_sql must be provided", error.message

        adapter = FakeAdapter.new
        intent = QueryIntent.new(
          adapter: adapter,
          raw_sql: "select 1",
          name: "User Load",
          binds: [1],
          prepare: true,
          allow_async: true,
          allow_retry: true,
          materialize_transactions: false,
          batch: true
        )
        intent.notification_payload = { sql: "select 1" }

        assert_equal adapter, intent.adapter
        assert_equal adapter.pool, intent.pool
        assert_equal "select 1", intent.raw_sql
        assert_equal "User Load", intent.name
        assert_equal ["cast-1"], intent.type_casted_binds
        assert_equal true, intent.has_binds?
        assert_includes intent.inspect, "User Load"
        assert_includes intent.inspect, "allow_retry=true"
        assert_equal({
          arel: nil,
          raw_sql: "select 1",
          processed_sql: "select 1",
          name: "User Load",
          binds: [1],
          prepare: true,
          allow_async: true,
          allow_retry: true,
          materialize_transactions: false,
          batch: true,
          type_casted_binds: ["cast-1"],
          notification_payload: { sql: "select 1" }
        }, intent.to_h)
      end

      def test_compile_arel_and_binds_are_memoized
        adapter = FakeAdapter.new
        intent = QueryIntent.new(adapter: adapter, arel: Object.new, binds: [:id], prepare: false, allow_retry: true)

        assert_equal "compiled SQL", intent.raw_sql
        assert_equal [:id, :compiled], intent.binds
        assert_equal true, intent.prepare
        assert_equal false, intent.allow_retry
        assert_equal ["cast-id", "cast-compiled"], intent.type_casted_binds
        assert_predicate intent, :has_binds?

        empty_intent = QueryIntent.new(adapter: FakeAdapter.new, raw_sql: "select 1")
        assert_not empty_intent.has_binds?
      end

      def test_processed_sql_checks_writes_and_applies_transformers
        adapter = FakeAdapter.new
        adapter.preventing_writes_value = true
        adapter.write_query_result = true
        intent = QueryIntent.new(adapter: adapter, raw_sql: "insert into users values (1)")

        error = assert_raises(ActiveRecord::ReadOnlyError) { intent.processed_sql }
        assert_match "Write query attempted while in readonly mode", error.message

        adapter = FakeAdapter.new
        old_transformers = ActiveRecord.query_transformers
        ActiveRecord.query_transformers = [->(sql, _adapter) { "#{sql} /* transformed */" }]
        assert_equal "select 1 /* transformed */", QueryIntent.new(adapter: adapter, raw_sql: "select 1").processed_sql

        ActiveRecord.query_transformers = nil
        assert_equal "select 2", QueryIntent.new(adapter: adapter, raw_sql: "select 2").processed_sql
      ensure
        ActiveRecord.query_transformers = old_transformers if defined?(old_transformers)
      end

      def test_write_query_heuristics_for_arel_and_raw_sql
        adapter = FakeAdapter.new
        select_intent = QueryIntent.new(adapter: adapter, arel: Arel::Table.new(name: :users).project(Arel.star))
        assert_not select_intent.send(:write_query?)

        insert_manager = Arel::InsertManager.new(Arel::Table.new(name: :users))
        insert_intent = QueryIntent.new(adapter: adapter, arel: insert_manager)
        assert insert_intent.send(:write_query?)

        raw_intent = QueryIntent.new(adapter: adapter, raw_sql: "delete from users")
        assert raw_intent.send(:write_query?)
        assert raw_intent.send(:write_query?) # memoized branch
      end

      def test_execute_sync_future_result_finish_and_result_order_guards
        adapter = FakeAdapter.new
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")

        assert_raises(RuntimeError, match: /before query has executed/) { intent.cast_result }
        assert_raises(RuntimeError, match: /before query has executed/) { intent.affected_rows }

        intent.execute!

        assert_equal false, intent.ran_async
        assert intent.raw_result_available?
        assert_equal :raw_result, intent.raw_result
        assert_equal [:cast, :raw_result], intent.cast_result
        assert_instance_of ActiveRecord::FutureResult::Complete, intent.future_result
        assert_raises(RuntimeError, match: /after cast_result/) { intent.affected_rows }

        affected_intent = QueryIntent.new(adapter: FakeAdapter.new, raw_sql: "update users set name = 'x'")
        affected_intent.execute!
        assert_equal 7, affected_intent.affected_rows
        assert_nil affected_intent.finish
        assert_raises(RuntimeError, match: /after affected_rows/) { affected_intent.cast_result }
      end

      def test_range_error_execution_returns_empty_result
        adapter = FakeAdapter.new
        adapter.raise_range = true
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select range")

        intent.execute!

        assert intent.raw_result_available?
        assert_empty intent.cast_result.to_a
      end

      def test_async_schedule_rejects_joinable_transactions_and_schedules_otherwise
        adapter = FakeAdapter.new
        adapter.async_enabled_value = true
        adapter.transaction = FakeTransaction.new(joinable: true)
        joinable_intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1", allow_async: true)

        assert_raises(ActiveRecord::AsynchronousQueryInsideTransactionError) { joinable_intent.execute! }

        adapter = FakeAdapter.new
        adapter.async_enabled_value = true
        session = FakeSession.new
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1", allow_async: true)
        ActiveRecord::Base.stub(:asynchronous_queries_session, session) do
          intent.execute!
        end

        assert_same session, intent.session
        assert_nil intent.adapter
        assert_equal [intent], adapter.pool.scheduled
        assert_instance_of ActiveRecord::FutureResult, intent.future_result
      end

      def test_pending_cancel_canceled_and_execute_or_skip_paths
        assert_nil QueryIntent.new(adapter: FakeAdapter.new, raw_sql: "select 1").pending?

        adapter = FakeAdapter.new
        session = FakeSession.new(active: false)
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = session

        assert_not intent.pending?
        assert intent.canceled?
        assert_nil intent.cancel
        assert_nil intent.execute_or_skip
        assert_empty adapter.executed_intents

        session.active = true
        intent.cancel
        assert_raises(ActiveRecord::FutureResult::Canceled) { intent.ensure_result }

        adapter = FakeAdapter.new
        session = FakeSession.new(active: true)
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = session
        intent.instance_variable_set(:@mutex, Mutex.new)

        intent.execute_or_skip

        assert_equal true, intent.ran_async
        assert_equal [intent], adapter.executed_intents
        assert intent.raw_result_available?
      end

      def test_execute_or_skip_restores_instrumenter_and_captures_errors
        adapter = FakeAdapter.new
        adapter.raise_error = RuntimeError.new("boom")
        previous = Object.new
        ActiveSupport::IsolatedExecutionState[:active_record_instrumenter] = previous
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = FakeSession.new(active: true)
        intent.instance_variable_set(:@mutex, Mutex.new)

        intent.execute_or_skip

        assert_same previous, ActiveSupport::IsolatedExecutionState[:active_record_instrumenter]
        assert_raises(RuntimeError, match: /boom/) { intent.ensure_result }
      ensure
        ActiveSupport::IsolatedExecutionState[:active_record_instrumenter] = nil
      end

      def test_execute_or_skip_returns_when_session_or_intent_stops_pending_mid_execution
        adapter = FakeAdapter.new
        session = FakeSession.new(active: true)
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = session
        intent.instance_variable_set(:@mutex, Mutex.new)
        def session.synchronize
          @active = false
          yield
        end

        assert_nil intent.execute_or_skip
        assert_empty adapter.executed_intents

        adapter = FakeAdapter.new
        session = FakeSession.new(active: true)
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = session
        intent.instance_variable_set(:@mutex, Mutex.new)
        adapter.pool.define_singleton_method(:with_connection) do |&block|
          session.active = false
          block.call(connection)
        end

        assert_nil intent.execute_or_skip
        assert_empty adapter.executed_intents
      end

      def test_execute_or_skip_returns_when_mutex_is_locked
        adapter = FakeAdapter.new
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = FakeSession.new(active: true)
        mutex = Mutex.new
        mutex.lock
        intent.instance_variable_set(:@mutex, mutex)

        assert_nil intent.execute_or_skip
        assert_empty adapter.executed_intents
      ensure
        mutex.unlock if mutex&.locked?
      end

      def test_ensure_result_waits_or_uses_existing_async_result
        adapter = FakeAdapter.new
        fallback_connection = FakeAdapter.new
        adapter.pool.connection = fallback_connection
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = FakeSession.new(active: true)
        intent.instance_variable_set(:@mutex, Mutex.new)

        intent.ensure_result

        assert_equal false, intent.ran_async
        assert_equal [intent], fallback_connection.executed_intents
        assert intent.raw_result_available?

        completed = QueryIntent.new(adapter: FakeAdapter.new, raw_sql: "select 1")
        completed.session = FakeSession.new(active: true)
        completed.raw_result = :already_done
        completed.ensure_result
        assert_equal 0.0, completed.lock_wait
      end

      def test_ensure_result_records_lock_wait_when_background_finished_while_waiting
        adapter = FakeAdapter.new
        session = FakeSession.new(active: true)
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = session
        fake_mutex = Class.new do
          def initialize(intent, session)
            @intent = intent
            @session = session
          end

          def synchronize
            @session.active = false
            @intent.raw_result = :done
            yield
          end
        end.new(intent, session)
        intent.instance_variable_set(:@mutex, fake_mutex)

        intent.ensure_result

        assert_operator intent.lock_wait, :>=, 0.0
      end

      def test_ensure_result_captures_foreground_fallback_errors
        adapter = FakeAdapter.new
        failing_connection = FakeAdapter.new
        failing_connection.raise_error = RuntimeError.new("foreground boom")
        adapter.pool.connection = failing_connection
        intent = QueryIntent.new(adapter: adapter, raw_sql: "select 1")
        intent.session = FakeSession.new(active: true)
        intent.instance_variable_set(:@mutex, Mutex.new)

        assert_raises(RuntimeError, match: /foreground boom/) { intent.ensure_result }
      end

      def test_event_buffer_records_and_flushes_events_with_lock_wait
        intent = QueryIntent.new(adapter: FakeAdapter.new, raw_sql: "select 1")
        intent.instance_variable_set(:@lock_wait, 12.5)
        instrumenter = FakeInstrumenter.new
        buffer = QueryIntent::EventBuffer.new(intent, instrumenter)
        published = []

        buffer.instrument("sql.active_record", { sql: "select 1" }) { :ok }
        ActiveSupport::Notifications.stub(:publish_event, ->(event) { published << event }) do
          buffer.flush
          buffer.flush
        end

        assert_equal 1, instrumenter.events.size
        assert_predicate instrumenter.events.first, :recorded
        assert_equal [instrumenter.events.first], published
        assert_equal 12.5, published.first.payload[:lock_wait]
      end
    end
  end
end
