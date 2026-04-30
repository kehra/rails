# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/cache"

class CacheEntryTest < ActiveSupport::TestCase
  def test_expired
    entry = ActiveSupport::Cache::Entry.new("value")
    assert_not entry.expired?, "entry not expired"
    entry = ActiveSupport::Cache::Entry.new("value", expires_in: 60)
    assert_not entry.expired?, "entry not expired"
    Time.stub(:now, Time.at(entry.expires_at + 1)) do
      assert_predicate entry, :expired?, "entry is expired"
    end
  end

  def test_initialize_with_expires_at
    entry = ActiveSupport::Cache::Entry.new("value", expires_in: 60)
    clone = ActiveSupport::Cache::Entry.new("value", expires_at: entry.expires_at)
    assert_equal entry.expires_at, clone.expires_at
  end

  def test_unpack_restores_value_expiry_and_version
    entry = ActiveSupport::Cache::Entry.unpack(["value", 123.0, "v1"])

    assert_equal "value", entry.value
    assert_equal 123.0, entry.expires_at
    assert_equal "v1", entry.version
  end

  def test_value_uncompresses_compressed_payload
    compressed = Zlib::Deflate.deflate(Marshal.dump(["value"]))
    entry = ActiveSupport::Cache::Entry.new(compressed, compressed: true)

    assert_equal ["value"], entry.value
  end

  def test_value_raises_deserialization_error_for_invalid_compressed_payload
    entry = ActiveSupport::Cache::Entry.new(Zlib::Deflate.deflate("\x04\x08".b), compressed: true)

    assert_raises(ActiveSupport::Cache::DeserializationError) { entry.value }
  end

  def test_mismatched_requires_both_versions
    assert ActiveSupport::Cache::Entry.new("value", version: "v1").mismatched?("v2")
    assert_not ActiveSupport::Cache::Entry.new("value", version: "v1").mismatched?("v1")
    assert_not ActiveSupport::Cache::Entry.new("value", version: "v1").mismatched?(nil)
    assert_not ActiveSupport::Cache::Entry.new("value").mismatched?("v1")
  end

  def test_expires_at_writer_accepts_nil_and_time
    entry = ActiveSupport::Cache::Entry.new("value", expires_in: 60)

    entry.expires_at = nil
    assert_nil entry.expires_at

    entry.expires_at = Time.at(123)
    assert_equal 123.0, entry.expires_at
  end

  def test_bytesize_for_nil_string_and_object
    assert_equal 0, ActiveSupport::Cache::Entry.new(nil).bytesize
    assert_equal 5, ActiveSupport::Cache::Entry.new("value").bytesize
    assert_equal Marshal.dump(["value"]).bytesize, ActiveSupport::Cache::Entry.new(["value"]).bytesize
  end

  def test_compressed_returns_self_for_already_compressed_entry
    entry = ActiveSupport::Cache::Entry.new("value", compressed: true)

    assert_same entry, entry.compressed(1)
  end

  def test_compressed_returns_self_for_immediate_values
    [nil, true, false, 1].each do |value|
      entry = ActiveSupport::Cache::Entry.new(value)
      assert_same entry, entry.compressed(1)
    end
  end

  def test_compressed_returns_self_when_payload_is_below_threshold_or_not_smaller
    small = ActiveSupport::Cache::Entry.new("small")
    assert_same small, small.compressed(1_000)

    incompressible = ActiveSupport::Cache::Entry.new(Random.bytes(64))
    assert_same incompressible, incompressible.compressed(1)
  end

  def test_compressed_returns_compressed_entry_when_smaller
    ActiveSupport::Cache::Entry.new(["x" * 1_000]).compressed(1)

    entry = ActiveSupport::Cache::Entry.new("x" * 1_000, version: "v1", expires_in: 60)
    compressed = entry.compressed(1)

    assert_not_same entry, compressed
    assert_predicate compressed, :compressed?
    assert_equal entry.value, compressed.value
    assert_equal entry.version, compressed.version
    assert_in_delta entry.expires_at, compressed.expires_at, 0.001
  end

  def test_local_is_false
    assert_not ActiveSupport::Cache::Entry.new("value").local?
  end

  def test_dup_value_duplicates_strings_and_objects_but_not_immediate_values_or_compressed_entries
    string = "value"
    entry = ActiveSupport::Cache::Entry.new(string)
    entry.dup_value!
    assert_equal string, entry.value
    assert_not_same string, entry.value

    object = ["value"]
    entry = ActiveSupport::Cache::Entry.new(object)
    entry.dup_value!
    assert_equal object, entry.value
    assert_not_same object, entry.value

    [nil, true, false, 1].each do |value|
      entry = ActiveSupport::Cache::Entry.new(value)
      assert_nothing_raised { entry.dup_value! }
      if value.nil?
        assert_nil entry.value
      else
        assert_equal value, entry.value
      end
    end

    compressed = ActiveSupport::Cache::Entry.new(Zlib::Deflate.deflate(Marshal.dump("value")), compressed: true)
    assert_nothing_raised { compressed.dup_value! }
    assert_equal "value", compressed.value
  end

  def test_pack_trims_trailing_nil_members
    assert_equal ["value"], ActiveSupport::Cache::Entry.new("value").pack
    assert_equal ["value", nil, "v1"], ActiveSupport::Cache::Entry.new("value", version: "v1").pack
  end
end
