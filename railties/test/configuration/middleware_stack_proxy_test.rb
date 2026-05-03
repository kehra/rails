# frozen_string_literal: true

require "active_support"
require "active_support/testing/autorun"
require "rails/configuration"
require "active_support/test_case"
require "minitest/mock"

module Rails
  module Configuration
    class MiddlewareStackProxyTest < ActiveSupport::TestCase
      def setup
        @stack = MiddlewareStackProxy.new
      end

      def test_playback_insert_before
        @stack.insert_before :foo
        assert_playback :insert_before, :foo
      end

      def test_playback_insert
        @stack.insert :foo
        assert_playback :insert_before, :foo
      end

      def test_playback_insert_after
        @stack.insert_after :foo
        assert_playback :insert_after, :foo
      end

      def test_playback_swap
        @stack.swap :foo
        assert_playback :swap, :foo
      end

      def test_playback_use
        @stack.use :foo
        assert_playback :use, :foo
      end

      def test_playback_delete
        @stack.delete :foo
        assert_playback :delete, :foo
      end

      def test_playback_move_before
        @stack.move_before :foo
        assert_playback :move_before, :foo
      end

      def test_playback_move
        @stack.move :foo
        assert_playback :move_before, :foo
      end

      def test_playback_move_after
        @stack.move_after :foo
        assert_playback :move_after, :foo
      end

      def test_playback_unshift
        @stack.unshift :foo
        assert_playback :unshift, :foo
      end

      def test_combining_proxies_preserves_regular_and_delete_operations
        other = MiddlewareStackProxy.new
        @stack.use :foo
        @stack.delete :bar
        other.unshift :baz
        other.move_after :qux

        combined = @stack + other

        assert_playback([:use, :unshift, :delete, :move_after], [:foo, :baz, :bar, :qux], combined)
      end

      def test_order
        @stack.swap :foo
        @stack.delete :foo

        assert_playback([:swap, :delete], :foo)
      end

      private
        def assert_playback(msg_names, args, stack = @stack)
          self.assertions += 1
          mock = Minitest::Mock.new
          args = Array(args)
          args *= Array(msg_names).length if args.length == 1
          Array(msg_names).zip(args).each do |msg_name, arg|
            mock.expect msg_name, nil, [arg]
          end
          stack.merge_into(mock)
          mock.verify
        end
    end
  end
end
