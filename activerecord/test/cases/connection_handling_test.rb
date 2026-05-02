# frozen_string_literal: true

require "cases/helper"
require "models/post"

module ActiveRecord
  class ConnectionHandlingTest < ActiveRecord::TestCase
    fixtures :posts

    setup do
      @_permanent_connection_checkout_was = ActiveRecord.permanent_connection_checkout
    end

    teardown do
      ActiveRecord.permanent_connection_checkout = @_permanent_connection_checkout_was
    end

    unless in_memory_db?
      test "#with_connection lease the connection for the duration of the block" do
        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        ActiveRecord::Base.with_connection do |connection|
          assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        end

        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?
      end

      test "#lease_connection makes the lease permanent even inside #with_connection" do
        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        conn = nil
        ActiveRecord::Base.with_connection do |connection|
          conn = connection
          assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
          2.times do
            assert_same connection, ActiveRecord::Base.lease_connection
          end
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same conn, ActiveRecord::Base.lease_connection
      end

      test "#lease_connection makes the lease permanent even inside #with_connection(prevent_permanent_checkout: true)" do
        ActiveRecord::Base.release_connection

        ActiveRecord::Base.with_connection(prevent_permanent_checkout: true) do |connection|
          assert_same connection, ActiveRecord::Base.lease_connection
        end

        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?
      end

      test "#with_connection use the already leased connection if available" do
        leased_connection = ActiveRecord::Base.lease_connection
        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?

        ActiveRecord::Base.with_connection do |connection|
          assert_same leased_connection, connection
          assert_same ActiveRecord::Base.lease_connection, connection
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same ActiveRecord::Base.lease_connection, leased_connection
      end

      test "#with_connection is reentrant" do
        leased_connection = ActiveRecord::Base.lease_connection
        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?

        ActiveRecord::Base.with_connection do |connection|
          assert_same leased_connection, connection
          assert_same ActiveRecord::Base.lease_connection, connection

          ActiveRecord::Base.with_connection do |connection2|
            assert_same leased_connection, connection2
            assert_same ActiveRecord::Base.lease_connection, connection2
          end
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same ActiveRecord::Base.lease_connection, leased_connection
      end

      test "#connection is a soft-deprecated alias to #lease_connection" do
        ActiveRecord.permanent_connection_checkout = true

        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        conn = nil
        ActiveRecord::Base.with_connection do |connection|
          conn = connection
          assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
          2.times do
            assert_same connection, ActiveRecord::Base.connection
          end
        end

        assert_predicate ActiveRecord::Base.connection_pool, :active_connection?
        assert_same conn, ActiveRecord::Base.connection

        ActiveRecord::Base.release_connection
      end

      test "#connection emits a deprecation warning if ActiveRecord.permanent_connection_checkout == :deprecated" do
        ActiveRecord.permanent_connection_checkout = :deprecated

        ActiveRecord::Base.release_connection

        assert_deprecated(ActiveRecord.deprecator) do
          ActiveRecord::Base.connection
        end

        assert_not_deprecated(ActiveRecord.deprecator) do
          ActiveRecord::Base.connection
        end

        ActiveRecord::Base.release_connection

        assert_deprecated(ActiveRecord.deprecator) do
          ActiveRecord::Base.connection
        end

        ActiveRecord::Base.release_connection

        ActiveRecord::Base.with_connection do
          assert_deprecated(ActiveRecord.deprecator) do
            ActiveRecord::Base.connection
          end
        end
      end

      test "#connection raises an error if ActiveRecord.permanent_connection_checkout == :disallowed" do
        ActiveRecord.permanent_connection_checkout = :disallowed

        ActiveRecord::Base.release_connection

        assert_raises(ActiveRecordError) do
          ActiveRecord::Base.connection
        end

        ActiveRecord::Base.with_connection do
          assert_raises(ActiveRecordError) do
            ActiveRecord::Base.connection
          end
        end

        ActiveRecord::Base.lease_connection

        assert_nothing_raised do
          ActiveRecord::Base.connection
        end
      end

      test "#connection doesn't make the lease permanent if inside #with_connection(prevent_permanent_checkout: true)" do
        ActiveRecord.permanent_connection_checkout = :disallowed

        ActiveRecord::Base.release_connection

        ActiveRecord::Base.with_connection(prevent_permanent_checkout: true) do |connection|
          assert_same connection, ActiveRecord::Base.connection
        end

        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?
      end

      test "common APIs don't permanently hold a connection when permanent checkout is deprecated or disallowed" do
        ActiveRecord.permanent_connection_checkout = :deprecated
        ActiveRecord::Base.release_connection
        assert_not_predicate ActiveRecord::Base.connection_pool, :active_connection?

        Post.create!(title: "foo", body: "bar")
        assert_not_predicate Post.connection_pool, :active_connection?

        Post.first
        assert_not_predicate Post.connection_pool, :active_connection?

        Post.count
        assert_not_predicate Post.connection_pool, :active_connection?
      end
    end

    test "#clear_query_caches_for_current_thread clears every connection pool" do
      pools = 2.times.map do
        pool = Object.new
        calls = []
        pool.define_singleton_method(:clear_query_cache) { calls << :clear_query_cache }
        pool.define_singleton_method(:calls) { calls }
        pool
      end
      handler = Object.new
      handler.define_singleton_method(:each_connection_pool) do |&block|
        pools.each(&block)
      end

      ActiveRecord::Base.stub(:connection_handler, handler) do
        ActiveRecord::Base.clear_query_caches_for_current_thread
      end

      assert_equal [[:clear_query_cache], [:clear_query_cache]], pools.map(&:calls)
    end

    test "#connected? delegates to the current connection specification role and shard" do
      handler = Object.new
      received = []
      handler.define_singleton_method(:connected?) do |specification_name, role:, shard:|
        received << [specification_name, role, shard]
        :connected_result
      end

      result = ActiveRecord::Base.stub(:connection_handler, handler) do
        ActiveRecord::Base.connected?
      end

      assert_equal :connected_result, result
      assert_equal [["ActiveRecord::Base", ActiveRecord::Base.current_role, ActiveRecord::Base.current_shard]], received
    end
  end
end
