# frozen_string_literal: true

require "cases/helper"
require "active_record/railties/controller_runtime"

module ActiveRecord
  module Railties
    class ControllerRuntimeTest < ActiveRecord::TestCase
      class InfoLogger
        def initialize(info)
          @info = info
        end

        def info?
          @info
        end
      end

      class BaseController
        attr_accessor :logger
        attr_reader :processed_actions, :payloads, :cleanup_calls

        def self.log_process_action(_payload)
          []
        end

        def initialize(logger: InfoLogger.new(true))
          @logger = logger
          @processed_actions = []
          @payloads = []
          @cleanup_calls = 0
        end

        def process(action)
          process_action(action)
        end

        def cleanup
          cleanup_view_runtime
        end

        def append(payload)
          append_info_to_payload(payload)
        end

        private
          def process_action(action, *args)
            @processed_actions << [action, args]
            :processed
          end

          def cleanup_view_runtime
            @cleanup_calls += 1
            ActiveRecord::RuntimeRegistry.record("render query", 7.0)
            100.0
          end

          def append_info_to_payload(payload)
            @payloads << payload
          end
      end

      class Controller < BaseController
        include ActiveRecord::Railties::ControllerRuntime
      end

      def setup
        super
        ActiveRecord::RuntimeRegistry.reset
      end

      def teardown
        ActiveRecord::RuntimeRegistry.reset
        super
      end

      def test_log_process_action_appends_active_record_runtime_message
        payload = { db_runtime: 12.34, queries_count: 1, cached_queries_count: 2 }

        messages = Controller.log_process_action(payload)

        assert_equal ["ActiveRecord: 12.3ms (1 query, 2 cached)"], messages
      end

      def test_log_process_action_pluralizes_queries_and_uses_zero_defaults
        payload = { db_runtime: 4.56 }

        messages = Controller.log_process_action(payload)

        assert_equal ["ActiveRecord: 4.6ms (0 queries, 0 cached)"], messages
      end

      def test_log_process_action_leaves_messages_when_db_runtime_is_absent
        assert_equal [], Controller.log_process_action({})
      end

      def test_initialize_sets_db_runtime_to_nil
        assert_nil Controller.new.send(:db_runtime)
      end

      def test_process_action_resets_runtime_before_delegating
        ActiveRecord::RuntimeRegistry.record("SELECT", 12.0)
        controller = Controller.new

        assert_equal :processed, controller.process(:show)
        assert_equal [[:show, []]], controller.processed_actions
        assert_equal 0.0, ActiveRecord::RuntimeRegistry.stats.sql_runtime
        assert_equal 0, ActiveRecord::RuntimeRegistry.stats.queries_count
      end

      def test_cleanup_view_runtime_tracks_database_runtime_and_subtracts_query_runtime
        controller = Controller.new
        ActiveRecord::RuntimeRegistry.record("before render", 7.0)

        runtime = controller.cleanup
        ActiveRecord::RuntimeRegistry.record("after render", 3.0)

        assert_equal 93.0, runtime
        assert_equal 14.0, controller.send(:db_runtime)
        assert_equal 3.0, ActiveRecord::RuntimeRegistry.stats.sql_runtime

        payload = {}
        controller.append(payload)

        assert_equal 17.0, payload[:db_runtime]
        assert_equal 3, payload[:queries_count]
        assert_equal 0, payload[:cached_queries_count]
        assert_equal 0.0, ActiveRecord::RuntimeRegistry.stats.sql_runtime
      end

      def test_cleanup_view_runtime_delegates_without_tracking_when_logger_is_not_info
        controller = Controller.new(logger: InfoLogger.new(false))
        ActiveRecord::RuntimeRegistry.record("SELECT", 5.0)

        assert_equal 100.0, controller.cleanup
        assert_nil controller.send(:db_runtime)
        assert_equal 12.0, ActiveRecord::RuntimeRegistry.stats.sql_runtime
      end

      def test_cleanup_view_runtime_delegates_without_tracking_when_logger_is_nil
        controller = Controller.new(logger: nil)
        ActiveRecord::RuntimeRegistry.record("SELECT", 5.0)

        assert_equal 100.0, controller.cleanup
        assert_nil controller.send(:db_runtime)
        assert_equal 12.0, ActiveRecord::RuntimeRegistry.stats.sql_runtime
      end
    end
  end
end
