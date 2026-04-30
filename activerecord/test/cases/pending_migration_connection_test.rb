# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  class PendingMigrationConnectionTest < ActiveRecord::TestCase
    class FakeConnectionHandler
      attr_reader :established, :removed

      def establish_connection(db_config, owner_name:)
        @established = [db_config, owner_name]
        :temporary_pool
      end

      def remove_connection_pool(owner_name)
        @removed = owner_name
      end
    end

    def test_with_temporary_pool_yields_established_pool_and_removes_it
      handler = FakeConnectionHandler.new

      ActiveRecord::Base.stub(:connection_handler, handler) do
        yielded = PendingMigrationConnection.with_temporary_pool(:db_config) { |pool| pool }

        assert_equal :temporary_pool, yielded
      end

      assert_equal [:db_config, PendingMigrationConnection], handler.established
      assert_equal "ActiveRecord::PendingMigrationConnection", handler.removed
    end

    def test_with_temporary_pool_removes_pool_when_block_raises
      handler = FakeConnectionHandler.new

      assert_raises(RuntimeError) do
        ActiveRecord::Base.stub(:connection_handler, handler) do
          PendingMigrationConnection.with_temporary_pool(:db_config) { raise "boom" }
        end
      end

      assert_equal "ActiveRecord::PendingMigrationConnection", handler.removed
    end

    def test_connection_role_flags_are_never_primary_or_preventing_writes
      assert_equal false, PendingMigrationConnection.primary_class?
      assert_equal false, PendingMigrationConnection.current_preventing_writes
    end
  end
end
