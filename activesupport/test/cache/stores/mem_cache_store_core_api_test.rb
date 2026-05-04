# frozen_string_literal: true

require_relative "../../abstract_unit"
require "active_support/cache"
require "dalli"

class MemCacheStoreCoreApiTest < ActiveSupport::TestCase
  class FakePool
    attr_reader :client

    def initialize(client = FakeClient.new)
      @client = client
    end

    def with
      yield client
    end
  end

  class FakeClient
    attr_reader :calls
    attr_accessor :values, :raise_on

    def initialize
      @calls = []
      @values = {}
    end

    def incr(*args)
      call(:incr, args)
      10
    end

    def decr(*args)
      call(:decr, args)
      2
    end

    def flush_all
      call(:flush_all, [])
      true
    end

    def stats
      call(:stats, [])
      { "localhost:11211" => { "curr_items" => "0" } }
    end

    def get(key, options = {})
      call(:get, [key, options])
      values[key]
    end

    def get_multi(keys)
      call(:get_multi, [keys])
      values.slice(*keys)
    end

    def set(*args, **options)
      call(:set, args, options)
      true
    end

    def add(*args, **options)
      call(:add, args, options)
      false
    end

    def delete(key)
      call(:delete, [key])
      true
    end

    private
      def call(method, args, options = nil)
        raise Dalli::DalliError, "failed" if raise_on == method
        calls << [method, args, options]
      end
  end

  def setup
    @client = FakeClient.new
    @pool = FakePool.new(@client)
    @cache = build_store
  end

  def test_supports_cache_versioning
    assert ActiveSupport::Cache::MemCacheStore.supports_cache_versioning?
  end

  def test_build_mem_cache_builds_plain_client_without_addresses
    fake = Object.new

    Dalli::Client.stub(:new, ->(addresses, options) {
      assert_nil addresses
      assert_equal({}, options)
      fake
    }) do
      assert_same fake, ActiveSupport::Cache::MemCacheStore.build_mem_cache(nil, pool: false)
    end
  end

  def test_build_mem_cache_wraps_client_in_connection_pool
    fake_pool = Object.new

    ConnectionPool.stub(:new, ->(**pool_options, &block) {
      assert_equal({ size: 2, timeout: 1 }, pool_options)
      Dalli::Client.stub(:new, ->(addresses, options) {
        assert_equal ["localhost:11211"], addresses
        assert_equal({ threadsafe: false }, options)
        :client
      }) { assert_equal :client, block.call }
      fake_pool
    }) do
      assert_same fake_pool, ActiveSupport::Cache::MemCacheStore.build_mem_cache("localhost:11211", pool: { size: 2, timeout: 1 })
    end
  end

  def test_initialize_accepts_cache_nils_and_inspect_uses_client
    cache = build_store(cache_nils: false)

    assert_match(/ActiveSupport::Cache::MemCacheStore/, cache.inspect)
    assert_match(/mem_cache=/, cache.inspect)
    assert_equal true, cache.options[:skip_nil]
  end

  def test_initialize_rejects_invalid_first_address
    assert_raises(ArgumentError) do
      build_store(Object.new)
    end
  end

  def test_increment_and_decrement_delegate_to_client
    assert_equal 10, @cache.increment("counter", 3, expires_in: 7)
    assert_equal 2, @cache.decrement("counter", 4, expires_in: 8)

    assert_equal :incr, @client.calls[0][0]
    assert_equal ["counter", 3, 7, 3], @client.calls[0][1]
    assert_equal :decr, @client.calls[1][0]
    assert_equal ["counter", 4, 8, 0], @client.calls[1][1]
  end

  def test_clear_and_stats_delegate_to_client
    assert @cache.clear
    assert_equal({ "localhost:11211" => { "curr_items" => "0" } }, @cache.stats)

    assert_equal [:flush_all, :stats], @client.calls.map(&:first)
  end

  def test_read_and_write_entries_delegate_to_client
    key = @cache.send(:normalize_key, "name", {})
    entry = ActiveSupport::Cache::Entry.new("value")

    assert @cache.send(:write_entry, key, entry)
    @client.values[key] = @client.calls.last[1][1]
    assert_equal "value", @cache.send(:read_entry, key).value
  end

  def test_write_serialized_entry_adds_when_unless_exist_is_set_and_extends_race_ttl_expiration
    @cache.send(:write_serialized_entry, "key", "payload", unless_exist: true, expires_in: 1, race_condition_ttl: 1)

    method, args, options = @client.calls.last
    assert_equal :add, method
    assert_equal ["key", "payload", 301], args
    assert_not options.key?(:compress)
  end

  def test_raw_serialization_and_deserialization
    entry = ActiveSupport::Cache::Entry.new(123)

    payload = @cache.send(:serialize_entry, entry, raw: true)
    assert_equal "123", payload
    assert_equal "123", @cache.send(:deserialize_entry, payload, raw: true).value
    assert_nil @cache.send(:deserialize_entry, nil, raw: true)
    assert_nil @cache.send(:deserialize_entry, nil, raw: false)
  end

  def test_read_multi_entries_filters_expired_mismatched_and_deserialization_errors
    good_key = @cache.send(:normalize_key, "good", {})
    expired_key = @cache.send(:normalize_key, "expired", {})
    mismatched_key = @cache.send(:normalize_key, "mismatched", version: "v1")
    broken_key = @cache.send(:normalize_key, "broken", {})

    @client.values[good_key] = @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("good"))
    @client.values[expired_key] = @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("expired", expires_in: -1))
    @client.values[mismatched_key] = @cache.send(:serialize_entry, ActiveSupport::Cache::Entry.new("mismatched", version: "v2"))
    @client.values[broken_key] = "broken"

    assert_equal({ "good" => "good" }, @cache.send(:read_multi_entries, ["good", "expired", "mismatched", "broken"], version: "v1"))
  end

  def test_normalize_key_escapes_binary_characters
    assert_equal "a%20%25%FF", @cache.send(:normalize_key, "a %\xFF".b, {})
  end


  def test_delete_entry_delegates_to_client
    assert @cache.send(:delete_entry, "key")
    assert_equal [:delete, ["key"], nil], @client.calls.last
  end

  def test_rescue_error_with_logs_reports_and_returns_fallback
    output = StringIO.new
    @cache.logger = ActiveSupport::Logger.new(output)

    assert_error_reported do
      assert_equal :fallback, @cache.send(:rescue_error_with, :fallback) { raise Dalli::DalliError, "failed" }
    end
    assert_includes output.string, "DalliError"
  end

  def test_rescue_error_with_handles_missing_logger_and_error_reporter
    @cache.logger = nil

    ActiveSupport.stub(:error_reporter, nil) do
      assert_equal :fallback, @cache.send(:rescue_error_with, :fallback) { raise Dalli::DalliError, "failed" }
    end
  end

  private
    def build_store(*addresses, **options)
      ActiveSupport::Cache::MemCacheStore.stub(:build_mem_cache, @pool) do
        ActiveSupport::Cache::MemCacheStore.new(*addresses, **options, pool: false)
      end
    end
end
