# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/cache"

class CacheStoreCoreApiTest < ActiveSupport::TestCase
  class DeserializationStore < ActiveSupport::Cache::Store
    attr_reader :writes

    BrokenEntry = Struct.new(:value_to_return) do
      def expired?
        false
      end

      def mismatched?(_version)
        false
      end

      def value
        raise ActiveSupport::Cache::DeserializationError
      end
    end

    def initialize(**options)
      super
      @writes = []
    end

    private
      def read_entry(_key, **)
        BrokenEntry.new
      end

      def write_entry(key, entry, **options)
        @writes << [key, entry, options]
        true
      end
  end

  class ScenarioStore < ActiveSupport::Cache::Store
    attr_accessor :entry

    private
      def read_entry(_key, **)
        entry
      end

      def delete_entry(_key, **)
        true
      end
  end

  class ScenarioEntry
    def initialize(expired: false, mismatched: false, value: "value")
      @expired = expired
      @mismatched = mismatched
      @value = value
    end

    def expired?
      @expired
    end

    def mismatched?(_version)
      @mismatched
    end

    def value
      @value
    end
  end

  class RaisingCoder
    def dump(_entry)
      "dumped"
    end

    def load(_payload)
      raise ActiveSupport::Cache::DeserializationError
    end
  end

  def test_retrieve_pool_options_rejects_invalid_pool_option
    error = assert_raises(TypeError) do
      ActiveSupport::Cache::Store.send(:retrieve_pool_options, pool: :invalid)
    end

    assert_equal "Invalid :pool argument, expected Hash, got: :invalid", error.message
  end

  def test_retrieve_pool_options_merges_empty_pool_options_with_defaults
    assert_equal ActiveSupport::Cache::Store::DEFAULT_POOL_OPTIONS, ActiveSupport::Cache::Store.send(:retrieve_pool_options, pool: {})
  end

  def test_retrieve_pool_options_returns_nil_when_merged_pool_options_are_empty
    stub_const(ActiveSupport::Cache::Store, :DEFAULT_POOL_OPTIONS, {}) do
      assert_nil ActiveSupport::Cache::Store.send(:retrieve_pool_options, pool: {})
    end
  end

  def test_silence_bang_and_mute_toggle_silence
    store = ActiveSupport::Cache::Store.new

    assert_same store, store.silence!
    assert_predicate store, :silence?

    yielded = false
    store.mute do
      yielded = true
      assert_predicate store, :silence?
    end

    assert yielded
    assert_predicate store, :silence?
  end

  def test_base_store_unsupported_operations_raise_not_implemented
    store = ActiveSupport::Cache::Store.new

    assert_raises(NotImplementedError) { store.delete_matched(/x/) }
    assert_raises(NotImplementedError) { store.increment("x") }
    assert_raises(NotImplementedError) { store.decrement("x") }
    assert_raises(NotImplementedError) { store.cleanup }
    assert_raises(NotImplementedError) { store.clear }
  end

  def test_base_store_required_entry_hooks_raise_not_implemented
    store = ActiveSupport::Cache::Store.new

    assert_raises(NotImplementedError) { store.send(:read_entry, "x") }
    assert_raises(NotImplementedError) { store.send(:write_entry, "x", ActiveSupport::Cache::Entry.new("v")) }
    assert_raises(NotImplementedError) { store.send(:delete_entry, "x") }
  end

  def test_read_treats_deserialization_error_as_a_miss
    store = DeserializationStore.new

    assert_nil store.read("broken")
  end

  def test_fetch_recalculates_after_deserialization_error
    store = DeserializationStore.new

    assert_equal "fresh", store.fetch("broken") { "fresh" }
    assert_equal 1, store.writes.size
  end

  def test_deserialize_entry_returns_nil_on_deserialization_error
    store = ActiveSupport::Cache::Store.new(coder: RaisingCoder.new)

    assert_nil store.send(:deserialize_entry, "payload")
  end

  def test_merged_options_returns_call_options_when_store_options_are_empty
    store = ActiveSupport::Cache::Store.new
    store.instance_variable_set(:@options, {})

    assert_equal({ expires_in: 1 }, store.send(:merged_options, expires_in: 1))
  end

  def test_invalid_expires_in_without_reporter_or_logger_is_ignored
    store = ActiveSupport::Cache::Store.new

    ActiveSupport.stub(:error_reporter, nil) do
      ActiveSupport::Cache::Store.stub(:logger, nil) do
        assert_nothing_raised do
          store.send(:handle_invalid_expires_in, "bad expiry")
        end
      end
    end
  end

  def test_fetch_allows_instrumentation_without_payload
    store = DeserializationStore.new

    instrument_without_payload(store) do
      assert_equal "fresh", store.fetch("broken") { "fresh" }
    end
  end

  def test_read_allows_instrumentation_without_payload_for_expired_entries
    store = ScenarioStore.new
    store.entry = ScenarioEntry.new(expired: true)

    instrument_without_payload(store) do
      assert_nil store.read("expired")
    end
  end

  def test_read_allows_instrumentation_without_payload_for_mismatched_entries
    store = ScenarioStore.new
    store.entry = ScenarioEntry.new(mismatched: true)

    instrument_without_payload(store) do
      assert_nil store.read("mismatched")
    end
  end

  def test_read_allows_instrumentation_without_payload_for_hits
    store = ScenarioStore.new
    store.entry = ScenarioEntry.new(value: "hit")

    instrument_without_payload(store) do
      assert_equal "hit", store.read("hit")
    end
  end

  def test_read_allows_instrumentation_without_payload_for_misses
    store = ScenarioStore.new

    instrument_without_payload(store) do
      assert_nil store.read("miss")
    end
  end

  def test_key_matcher_evaluates_proc_namespaces
    store = ActiveSupport::Cache::Store.new(namespace: -> { "proc_namespace" })

    assert_equal(/^proc_namespace:foo/, store.send(:key_matcher, /^foo/, store.options))
  end

  def test_instrument_logs_without_key_details
    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    logger.level = Logger::DEBUG
    store = ActiveSupport::Cache::Store.new

    ActiveSupport::Cache::Store.stub(:logger, logger) do
      store.send(:instrument, :custom, nil) { }
    end

    assert_includes output.string, "Cache custom"
  end

  private
    def instrument_without_payload(store)
      store.define_singleton_method(:instrument) do |*, &block|
        block.call(nil)
      end

      yield
    end
end
