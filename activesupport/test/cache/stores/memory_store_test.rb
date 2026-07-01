# frozen_string_literal: true

require_relative "../../abstract_unit"
require "active_support/cache"
require_relative "../behaviors"

class StoreTest < ActiveSupport::TestCase
  def lookup_store(options = {})
    ActiveSupport::Cache.lookup_store(:memory_store, options)
  end
end

class MemoryStoreTest < StoreTest
  include CacheStoreBehavior
  include CacheStoreVersionBehavior
  include CacheStoreCoderBehavior
  include CacheStoreCompressionBehavior
  include CacheStoreSerializerBehavior
  include CacheDeleteMatchedBehavior
  include CacheIncrementDecrementBehavior
  include CacheInstrumentationBehavior
  include CacheLoggingBehavior

  def setup
    @cache = lookup_store(expires_in: 60)
  end

  def test_supports_cache_versioning
    assert ActiveSupport::Cache::MemoryStore.supports_cache_versioning?
  end

  def test_local_store_read_entry_and_unset_local_cache
    @cache.new_local_cache
    local = @cache.local_cache
    local.write_entry("key", "payload")

    assert_equal "payload", local.read_entry("key")

    @cache.unset_local_cache
    assert_nil @cache.local_cache
  end

  def test_cleanup_without_local_cache_delegates_to_store
    assert_nothing_raised { @cache.cleanup }
  end

  def test_cleanup_with_local_cache_clears_local_entries
    @cache.with_local_cache do
      @cache.write("name", "local")
      @cache.unset_local_cache
      @cache.write("name", "remote")
      @cache.new_local_cache
      local_key = @cache.send(:normalize_key, "name", {})
      local_entry = @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("local"))
      @cache.local_cache.write_entry(local_key, local_entry)

      @cache.cleanup

      assert_equal "remote", @cache.read("name")
    end
  end

  def test_local_cache_fetch_multi_handles_recorded_misses
    @cache.with_local_cache do
      missing_key = @cache.send(:normalize_key, "missing", {})
      @cache.local_cache.write_entry(missing_key, nil)

      assert_equal({ "missing" => "fresh-missing" }, @cache.fetch_multi("missing") { |name| "fresh-#{name}" })
    end
  end

  def test_local_cache_fetch_multi_handles_nil_and_expired_local_entries
    @cache.with_local_cache do
      invalid_key = @cache.send(:normalize_key, "invalid", {})
      expired_key = @cache.send(:normalize_key, "expired", {})
      @cache.local_cache.write_entry(invalid_key, @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("invalid")))
      @cache.local_cache.write_entry(expired_key, @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("old", expires_in: -1)))

      result = @cache.stub(:deserialize_entry, nil) do
        @cache.fetch_multi("invalid") { |name| "fresh-#{name}" }
      end
      assert_nil result["invalid"]

      result = @cache.fetch_multi("expired") { |name| "fresh-#{name}" }
      assert_equal "fresh-expired", result["expired"]
    end
  end

  def test_local_cache_read_multi_handles_nil_local_entries
    @cache.with_local_cache do
      invalid_key = @cache.send(:normalize_key, "invalid", {})
      @cache.local_cache.write_entry(invalid_key, @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("invalid")))

      result = @cache.stub(:deserialize_entry, nil) do
        @cache.send(:read_multi_entries, ["invalid"])
      end
      assert_equal({ "invalid" => nil }, result)
    end
  end

  def test_clear_removes_entries_and_resets_size
    @cache.write("name", "value")

    @cache.clear

    assert_nil @cache.read("name")
    assert_equal 0, @cache.instance_variable_get(:@cache_size)
  end

  def test_cleanup_ignores_live_entries
    @cache.write("name", "value")

    assert_nothing_raised { @cache.cleanup }
    assert_equal "value", @cache.read("name")
  end

  def test_cleanup_deletes_expired_entries_without_reading_first
    key = @cache.send(:normalize_key, "expired", {})
    @cache.send(:write_entry, key, ActiveSupport::Cache::Entry.new("value", expires_in: -1))

    @cache.cleanup

    assert_nil @cache.read("expired")
  end

  def test_prune_returns_while_already_pruning
    @cache.instance_variable_set(:@pruning, true)

    assert_nil @cache.prune(0)
    assert_predicate @cache, :pruning?
  ensure
    @cache.instance_variable_set(:@pruning, false) if @cache
  end

  def test_inspect_includes_entries_size_and_options
    assert_match(/entries=0/, @cache.inspect)
    assert_match(/size=0/, @cache.inspect)
    assert_match(/options=/, @cache.inspect)
  end

  def test_increment_preserves_expiry
    @cache = lookup_store
    @cache.write("counter", 1, raw: true, expires_in: 30.seconds)
    assert_equal 1, @cache.read("counter", raw: true)

    Time.stub(:now, Time.now + 1.minute) do
      assert_nil @cache.read("counter", raw: true)
    end

    @cache.write("counter", 1, raw: true, expires_in: 30.seconds)
    @cache.increment("counter")
    assert_equal 2, @cache.read("counter", raw: true)
    Time.stub(:now, Time.now + 1.minute) do
      assert_nil @cache.read("counter", raw: true)
    end

    @cache.write("counter", 1, raw: true)
    @cache.increment("counter", expires_in: 30)
    assert_equal 2, @cache.read("counter", raw: true)
    Time.stub(:now, Time.now + 1.minute) do
      assert_nil @cache.read("counter2", raw: true)
    end
  end

  def test_cleanup_instrumentation
    size = 3
    size.times { |i| @cache.write(i.to_s, i) }

    assert_notification("cache_cleanup.active_support", size: size, store: @cache.class.name) do
      @cache.cleanup
    end
  end

  def test_cleanup_with_non_dup_coder_serializer
    @cache = lookup_store(serializer: :marshal_7_1)
    @cache.write("expired", "x" * 100, expires_in: 0.01)
    @cache.write("fresh", "y" * 100)

    Time.stub(:now, Time.now + 1.minute) do
      @cache.cleanup

      assert_nil @cache.read("expired")
      assert_equal "y" * 100, @cache.read("fresh")
    end
  end

  def test_nil_coder_bypasses_mutation_safeguard
    @cache = lookup_store(coder: nil)
    value = {}
    @cache.write("key", value)

    assert_same value, @cache.read("key")
  end

  def test_write_with_unless_exist
    assert_equal true, @cache.write(1, "aaaaaaaaaa")
    assert_equal false, @cache.write(1, "aaaaaaaaaa", unless_exist: true)
    @cache.write(1, nil)
    assert_equal false, @cache.write(1, "aaaaaaaaaa", unless_exist: true)
  end

  def test_namespaced_write_with_unless_exist
    namespaced_cache = lookup_store(expires_in: 60, namespace: "foo")

    assert_equal true, namespaced_cache.write(1, "aaaaaaaaaa")
    assert_equal false, namespaced_cache.write(1, "aaaaaaaaaa", unless_exist: true)
    namespaced_cache.write(1, nil)
    assert_equal false, namespaced_cache.write(1, "aaaaaaaaaa", unless_exist: true)
  end

  def test_write_expired_value_with_unless_exist
    assert_equal true, @cache.write(1, "aaaa", expires_in: 1.second)
    travel 2.seconds
    assert_equal true, @cache.write(1, "bbbb", expires_in: 1.second, unless_exist: true)
  end

  private
    def compression_always_disabled_by_default?
      true
    end
end

class MemoryStorePruningTest < StoreTest
  def setup
    @record_size = ActiveSupport::Cache.lookup_store(:memory_store).send(:cached_size, 1, ActiveSupport::Cache::Entry.new("aaaaaaaaaa"))
    @cache = ActiveSupport::Cache.lookup_store(:memory_store, expires_in: 60, size: @record_size * 10 + 1)
  end

  def test_prune_size
    @cache.write(1, "aaaaaaaaaa") && sleep(0.001)
    @cache.write(2, "bbbbbbbbbb") && sleep(0.001)
    @cache.write(3, "cccccccccc") && sleep(0.001)
    @cache.write(4, "dddddddddd") && sleep(0.001)
    @cache.write(5, "eeeeeeeeee") && sleep(0.001)
    @cache.read(2) && sleep(0.001)
    @cache.read(4)
    @cache.prune(@record_size * 3)
    assert @cache.exist?(5)
    assert @cache.exist?(4)
    assert_not @cache.exist?(3), "no entry"
    assert @cache.exist?(2)
    assert_not @cache.exist?(1), "no entry"
  end

  def test_prune_size_on_write
    @cache.write(1, "aaaaaaaaaa") && sleep(0.001)
    @cache.write(2, "bbbbbbbbbb") && sleep(0.001)
    @cache.write(3, "cccccccccc") && sleep(0.001)
    @cache.write(4, "dddddddddd") && sleep(0.001)
    @cache.write(5, "eeeeeeeeee") && sleep(0.001)
    @cache.write(6, "ffffffffff") && sleep(0.001)
    @cache.write(7, "gggggggggg") && sleep(0.001)
    @cache.write(8, "hhhhhhhhhh") && sleep(0.001)
    @cache.write(9, "iiiiiiiiii") && sleep(0.001)
    @cache.write(10, "kkkkkkkkkk") && sleep(0.001)
    @cache.read(2) && sleep(0.001)
    @cache.read(4) && sleep(0.001)
    @cache.write(11, "llllllllll")
    assert @cache.exist?(11)
    assert @cache.exist?(10)
    assert @cache.exist?(9)
    assert @cache.exist?(8)
    assert @cache.exist?(7)
    assert_not @cache.exist?(6), "no entry"
    assert_not @cache.exist?(5), "no entry"
    assert @cache.exist?(4)
    assert_not @cache.exist?(3), "no entry"
    assert @cache.exist?(2)
    assert_not @cache.exist?(1), "no entry"
  end

  def test_prune_size_on_write_based_on_key_length
    @cache.write(1, "aaaaaaaaaa") && sleep(0.001)
    @cache.write(2, "bbbbbbbbbb") && sleep(0.001)
    @cache.write(3, "cccccccccc") && sleep(0.001)
    @cache.write(4, "dddddddddd") && sleep(0.001)
    @cache.write(5, "eeeeeeeeee") && sleep(0.001)
    @cache.write(6, "ffffffffff") && sleep(0.001)
    @cache.write(7, "gggggggggg") && sleep(0.001)
    @cache.write(8, "hhhhhhhhhh") && sleep(0.001)
    @cache.write(9, "iiiiiiiiii") && sleep(0.001)
    long_key = "*" * 2 * @record_size
    @cache.write(long_key, "llllllllll")
    assert @cache.exist?(long_key)
    assert @cache.exist?(9)
    assert @cache.exist?(8)
    assert @cache.exist?(7)
    assert @cache.exist?(6)
    assert @cache.exist?(5)
    assert_not @cache.exist?(4), "no entry"
    assert_not @cache.exist?(3), "no entry"
    assert_not @cache.exist?(2), "no entry"
    assert_not @cache.exist?(1), "no entry"
  end

  def test_pruning_is_capped_at_a_max_time
    def @cache.delete_entry(*args, **options)
      sleep(0.01)
      super
    end
    @cache.write(1, "aaaaaaaaaa") && sleep(0.001)
    @cache.write(2, "bbbbbbbbbb") && sleep(0.001)
    @cache.write(3, "cccccccccc") && sleep(0.001)
    @cache.write(4, "dddddddddd") && sleep(0.001)
    @cache.write(5, "eeeeeeeeee") && sleep(0.001)
    @cache.prune(30, 0.001)
    assert @cache.exist?(5)
    assert @cache.exist?(4)
    assert @cache.exist?(3)
    assert @cache.exist?(2)
    assert_not @cache.exist?(1)
  end

  def test_cache_not_mutated
    item = { "foo" => "bar" }
    key = "test_key"
    @cache.write(key, item)

    read_item = @cache.read(key)
    read_item["foo"] = "xyz"
    assert_equal item, @cache.read(key)
  end

  def test_cache_different_object_ids_hash
    item = { "foo" => "bar" }
    key = "test_key"
    @cache.write(key, item)

    read_item = @cache.read(key)
    assert_not_equal item.object_id, read_item.object_id
    assert_not_equal read_item.object_id, @cache.read(key).object_id
  end

  def test_cache_different_object_ids_string
    item = "my_string"
    key = "test_key"
    @cache.write(key, item)

    read_item = @cache.read(key)
    assert_not_equal item.object_id, read_item.object_id
    assert_not_equal read_item.object_id, @cache.read(key).object_id
  end

  def test_local_store_strategy
    @cache.with_local_cache do
      @cache.write("name", "value")
      assert_equal "value", @cache.read("name")
      @cache.delete("name")
      assert_nil @cache.read("name")
      @cache.write("name", "value")
    end
    assert_equal "value", @cache.read("name")
  end

  def test_local_store_repeated_reads
    @cache.with_local_cache do
      @cache.read("foo")
      assert_nil @cache.read("foo")

      @cache.read_multi("foo", "bar")
      assert_equal({}, @cache.read_multi("foo", "bar"))
    end
  end
end
