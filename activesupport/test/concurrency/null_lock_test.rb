# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/concurrency/null_lock"

module ActiveSupport
  module Concurrency
    class NullLockTest < ActiveSupport::TestCase
      def test_synchronize_yields_and_returns_block_value
        yielded = false

        result = NullLock.synchronize do
          yielded = true
          :result
        end

        assert yielded
        assert_equal :result, result
      end
    end
  end
end
