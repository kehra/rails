# frozen_string_literal: true

require_relative "../abstract_unit"

module ActiveSupport
  module Notifications
    class EventedTest < ActiveSupport::TestCase
      # we expect all exception types to be handled, so test with the most basic type
      class BadListenerException < Exception; end

      class Listener
        attr_reader :events

        def initialize
          @events = []
        end

        def start(name, id, payload)
          @events << [:start, name, id, payload]
        end

        def finish(name, id, payload)
          @events << [:finish, name, id, payload]
        end
      end

      class ListenerWithTimedSupport < Listener
        def call(name, start, finish, id, payload)
          @events << [:call, name, start, finish, id, payload]
        end
      end

      class BadStartListener < Listener
        def start(name, id, payload)
          raise BadListenerException
        end

        def finish(name, id, payload)
        end
      end

      class BadFinishListener < Listener
        def start(name, id, payload)
        end

        def finish(name, id, payload)
          raise BadListenerException
        end
      end

      class PublishEventListener < Listener
        def publish_event(event)
          @events << [:publish_event, event]
        end
      end

      class SilenceableListener < Listener
        attr_writer :silenced

        def initialize
          super
          @silenced = true
        end

        def silenced?(name)
          @events << [:silenced?, name]
          @silenced
        end
      end

      class SilenceableTimedListener
        attr_reader :events
        attr_writer :silenced

        def initialize
          @events = []
          @silenced = false
        end

        def call(name, start, finish, id, payload)
          @events << [:call, name, start, finish, id, payload]
        end

        def silenced?(name)
          @events << [:silenced?, name]
          @silenced
        end
      end

      def test_evented_listener
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe "hi", listener
        notifier.start  "hi", 1, {}
        notifier.start  "hi", 2, {}
        notifier.finish "hi", 2, {}
        notifier.finish "hi", 1, {}

        assert_equal 4, listener.events.length
        assert_equal [
          [:start, "hi", 1, {}],
          [:start, "hi", 2, {}],
          [:finish, "hi", 2, {}],
          [:finish, "hi", 1, {}],
        ], listener.events
      end

      def test_evented_listener_no_events
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe "hi", listener
        notifier.start  "world", 1, {}
        assert_equal 0, listener.events.length
      end

      def test_evented_listener_without_publish_support_ignores_publish
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe "hi", listener

        assert_nothing_raised { notifier.publish "hi", Time.now, Time.now, 1, {} }
        assert_empty listener.events
      end

      def test_evented_listener_with_publish_event_support_receives_event
        notifier = Fanout.new
        listener = PublishEventListener.new
        event = Event.new("hi", Time.now, Time.now, 1, {})
        notifier.subscribe "hi", listener

        notifier.publish_event event

        assert_equal [[:publish_event, event]], listener.events
      end

      def test_silenceable_evented_listener_can_be_reactivated_after_groups_are_cached
        notifier = Fanout.new
        silenceable = SilenceableListener.new
        listener = Listener.new
        notifier.subscribe "hi", silenceable
        notifier.subscribe "hi", listener

        notifier.start "hi", 1, {}
        notifier.finish "hi", 1, {}
        assert_equal [[:silenced?, "hi"]], silenceable.events
        assert_equal [[:start, "hi", 1, {}], [:finish, "hi", 1, {}]], listener.events

        silenceable.silenced = false
        notifier.start "hi", 2, {}
        notifier.finish "hi", 2, {}

        assert_includes silenceable.events, [:start, "hi", 2, {}]
        assert_includes silenceable.events, [:finish, "hi", 2, {}]
      end

      def test_active_silenceable_groups_are_added_when_no_unsilenced_group_exists
        notifier = Fanout.new
        timed = SilenceableTimedListener.new
        evented = SilenceableListener.new
        evented.silenced = false
        notifier.subscribe "hi", timed
        notifier.subscribe "hi", evented

        notifier.start "hi", 1, {}
        notifier.finish "hi", 1, {}

        assert_includes evented.events, [:start, "hi", 1, {}]
        assert_includes evented.events, [:finish, "hi", 1, {}]
        assert_equal :call, timed.events.last.first
      end

      def test_listen_to_everything
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe nil, listener
        notifier.start  "hello", 1, {}
        notifier.start  "world", 1, {}
        notifier.finish  "world", 1, {}
        notifier.finish  "hello", 1, {}

        assert_equal 4, listener.events.length
        assert_equal [
          [:start,  "hello", 1, {}],
          [:start,  "world", 1, {}],
          [:finish,  "world", 1, {}],
          [:finish,  "hello", 1, {}],
        ], listener.events
      end

      def test_listen_start_single_exception_consistency
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe nil, BadStartListener.new
        notifier.subscribe nil, listener

        assert_raises BadListenerException do
          notifier.start "hello", 1, {}
        end

        notifier.finish "hello", 1, {}

        assert_equal [[:start, "hello", 1, {}], [:finish, "hello", 1, {}]], listener.events
      end

      def test_listen_start_multiple_exception_consistency
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe nil, BadStartListener.new
        notifier.subscribe nil, BadStartListener.new
        notifier.subscribe nil, listener

        error = assert_raises InstrumentationSubscriberError do
          notifier.start  "hello", 1, {}
        end
        assert_instance_of BadListenerException, error.cause

        error = assert_raises InstrumentationSubscriberError do
          notifier.start  "world", 1, {}
        end
        assert_instance_of BadListenerException, error.cause

        notifier.finish  "world", 1, {}
        notifier.finish  "hello", 1, {}

        assert_equal 4, listener.events.length
        assert_equal [
          [:start,  "hello", 1, {}],
          [:start,  "world", 1, {}],
          [:finish,  "world", 1, {}],
          [:finish,  "hello", 1, {}],
        ], listener.events
      end

      def test_listen_finish_multiple_exception_consistency
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe nil, BadFinishListener.new
        notifier.subscribe nil, BadFinishListener.new
        notifier.subscribe(nil) { |*args| raise "foo" }
        notifier.subscribe(nil) { |obj| raise "foo" }
        notifier.subscribe(nil, monotonic: true) { |obj| raise "foo" }
        notifier.subscribe nil, listener

        notifier.start  "hello", 1, {}
        notifier.start  "world", 1, {}
        error = assert_raises InstrumentationSubscriberError do
          notifier.finish  "world", 1, {}
        end
        assert_equal 5, error.exceptions.count
        assert_instance_of BadListenerException, error.cause

        error = assert_raises InstrumentationSubscriberError do
          notifier.finish  "hello", 1, {}
        end
        assert_equal 5, error.exceptions.count
        assert_instance_of BadListenerException, error.cause

        assert_equal 4, listener.events.length
        assert_equal [
          [:start,  "hello", 1, {}],
          [:start,  "world", 1, {}],
          [:finish,  "world", 1, {}],
          [:finish,  "hello", 1, {}],
        ], listener.events
      end

      def test_evented_listener_priority
        notifier = Fanout.new
        listener = ListenerWithTimedSupport.new
        notifier.subscribe "hi", listener

        notifier.start "hi", 1, {}
        notifier.finish "hi", 1, {}

        assert_equal [
          [:start, "hi", 1, {}],
          [:finish, "hi", 1, {}]
        ], listener.events
      end

      def test_handle_cannot_finish_before_starting
        notifier = Fanout.new
        notifier.subscribe "hi", Listener.new
        handle = notifier.build_handle("hi", 1, {})

        error = assert_raises ArgumentError do
          handle.finish
        end

        assert_equal "expected state to be :started but was :initialized", error.message
      end

      def test_regexp_unsubscribe_ignores_non_matching_name
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe(/[a-z]*.world/, listener)

        notifier.unsubscribe("not.matched")
        notifier.start("hi.world", 1, {})
        notifier.finish("hi.world", 2, {})

        assert_equal [
          [:start, "hi.world", 1, {}],
          [:finish, "hi.world", 2, {}],
        ], listener.events
      end

      def test_listen_to_regexp
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe(/[a-z]*.world/, listener)
        notifier.start("hi.world", 1, {})
        notifier.finish("hi.world", 2, {})
        notifier.start("hello.world", 1, {})
        notifier.finish("hello.world", 2, {})

        assert_equal [
          [:start, "hi.world", 1, {}],
          [:finish, "hi.world", 2, {}],
          [:start, "hello.world", 1, {}],
          [:finish, "hello.world", 2, {}]
        ], listener.events
      end

      def test_listen_to_regexp_with_exclusions
        notifier = Fanout.new
        listener = Listener.new
        notifier.subscribe(/[a-z]*.world/, listener)
        notifier.unsubscribe("hi.world")
        notifier.start("hi.world", 1, {})
        notifier.finish("hi.world", 2, {})
        notifier.start("hello.world", 1, {})
        notifier.finish("hello.world", 2, {})

        assert_equal [
          [:start, "hello.world", 1, {}],
          [:finish, "hello.world", 2, {}]
        ], listener.events
      end
    end
  end
end
