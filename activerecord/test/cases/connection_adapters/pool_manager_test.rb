# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module ConnectionAdapters
    class PoolManagerTest < ActiveRecord::TestCase
      def test_empty_manager_has_no_roles_shards_or_pool_configs
        manager = PoolManager.new

        assert_empty manager.role_names
        assert_empty manager.shard_names
        assert_empty manager.pool_configs
        assert_empty manager.pool_configs(:writing)
        assert_nil manager.get_pool_config(:writing, :default)
      end

      def test_set_and_get_pool_config_by_role_and_shard
        manager = PoolManager.new
        writing_default = Object.new
        writing_shard_one = Object.new
        reading_default = Object.new

        manager.set_pool_config(:writing, :default, writing_default)
        manager.set_pool_config(:writing, :shard_one, writing_shard_one)
        manager.set_pool_config(:reading, :default, reading_default)

        assert_equal [:writing, :reading], manager.role_names
        assert_equal [:default, :shard_one], manager.shard_names
        assert_equal writing_default, manager.get_pool_config(:writing, :default)
        assert_equal writing_shard_one, manager.get_pool_config(:writing, :shard_one)
        assert_equal reading_default, manager.get_pool_config(:reading, :default)
        assert_equal [writing_default, writing_shard_one], manager.pool_configs(:writing)
        assert_equal [writing_default, writing_shard_one, reading_default], manager.pool_configs
      end

      def test_each_pool_config_iterates_for_specific_role_or_all_roles
        manager = PoolManager.new
        writing_default = Object.new
        writing_shard_one = Object.new
        reading_default = Object.new
        manager.set_pool_config(:writing, :default, writing_default)
        manager.set_pool_config(:writing, :shard_one, writing_shard_one)
        manager.set_pool_config(:reading, :default, reading_default)

        writing_configs = []
        manager.each_pool_config(:writing) { |config| writing_configs << config }
        assert_equal [writing_default, writing_shard_one], writing_configs

        all_configs = []
        manager.each_pool_config { |config| all_configs << config }
        assert_equal [writing_default, writing_shard_one, reading_default], all_configs
      end

      def test_remove_pool_config_and_role
        manager = PoolManager.new
        writing_default = Object.new
        reading_default = Object.new
        manager.set_pool_config(:writing, :default, writing_default)
        manager.set_pool_config(:reading, :default, reading_default)

        assert_equal writing_default, manager.remove_pool_config(:writing, :default)
        assert_nil manager.get_pool_config(:writing, :default)
        assert_equal({ default: reading_default }, manager.remove_role(:reading))
        assert_empty manager.pool_configs(:reading)
      end

      def test_set_pool_config_rejects_nil_with_actionable_message
        manager = PoolManager.new

        error = assert_raises(ArgumentError) do
          manager.set_pool_config(:reading, :shard_one, nil)
        end

        assert_match "The `pool_config` for the :reading role and :shard_one shard was `nil`", error.message
        assert_match "config.active_record.writing_role", error.message
        assert_match "reading_role", error.message
      end
    end
  end
end
