# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class StatementPoolTest < ActiveRecord::TestCase
      class TestPool < StatementPool
        attr_reader :deallocated

        def initialize(*args)
          super
          @deallocated = []
        end

        private
          def dealloc(stmt)
            raise ArgumentError unless stmt
            @deallocated << stmt
          end
      end

      setup do
        @pool = TestPool.new
      end

      test "#delete doesn't call dealloc if the statement didn't exist" do
        stmt = Object.new
        sql = "SELECT 1"
        @pool[sql] = stmt
        assert_same stmt, @pool[sql]
        assert_same stmt, @pool.delete(sql)
        assert_equal [stmt], @pool.deallocated
        assert_nil @pool.delete(sql)
      end

      test "enumerable and lookup methods expose current process cache" do
        first = Object.new
        second = Object.new
        @pool["SELECT 1"] = first
        @pool["SELECT 2"] = second

        assert @pool.key?("SELECT 1")
        assert_equal 2, @pool.length
        assert_equal [["SELECT 1", first], ["SELECT 2", second]], @pool.each.to_a
      end

      test "statement limit evicts and deallocates oldest statements" do
        pool = TestPool.new(2)
        first = Object.new
        second = Object.new
        third = Object.new

        pool["SELECT 1"] = first
        pool["SELECT 2"] = second
        pool["SELECT 3"] = third

        assert_nil pool["SELECT 1"]
        assert_same second, pool["SELECT 2"]
        assert_same third, pool["SELECT 3"]
        assert_equal [first], pool.deallocated
      end

      test "clear deallocates statements and reset clears without deallocation" do
        first = Object.new
        second = Object.new
        @pool["SELECT 1"] = first
        @pool["SELECT 2"] = second

        @pool.clear

        assert_equal 0, @pool.length
        assert_equal [first, second], @pool.deallocated

        third = Object.new
        @pool["SELECT 3"] = third
        @pool.reset

        assert_equal 0, @pool.length
        assert_equal [first, second], @pool.deallocated
      end

      test "base dealloc raises not implemented" do
        pool = StatementPool.new
        pool["SELECT 1"] = Object.new

        assert_raises(NotImplementedError) do
          pool.clear
        end
      end
    end
  end
end
