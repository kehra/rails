# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/core_ext/object/with"

class CacheSerializerWithFallbackTest < ActiveSupport::TestCase
  FORMATS = ActiveSupport::Cache::SerializerWithFallback::SERIALIZERS.keys
  LEGACY_FORMATS = [:passthrough, :marshal_7_0].freeze

  setup do
    @entry = ActiveSupport::Cache::Entry.new(
      [{ a_boolean: false, a_number: 123, a_string: "x" * 40 }], expires_in: 100, version: "v42"
    )
  end

  FORMATS.product(FORMATS - LEGACY_FORMATS) do |loader, dumper|
    test "#{loader.inspect} serializer can load #{dumper.inspect} dump" do
      dumped = serializer(dumper).dump(@entry.value)
      assert_equal @entry.value, serializer(loader).load(dumped)
    end
  end

  FORMATS.product(LEGACY_FORMATS) do |loader, dumper|
    test "#{loader.inspect} serializer can load #{dumper.inspect} dump" do
      dumped = serializer(dumper).dump(@entry)
      assert_entry @entry, serializer(loader).load(dumped)
    end
  end

  FORMATS.each do |format|
    test "#{format.inspect} serializer handles unrecognized payloads gracefully" do
      assert_nil serializer(format).load(Object.new)
      assert_nil serializer(format).load("")
    end

    test "#{format.inspect} serializer logs unrecognized payloads" do
      assert_logs(/unrecognized/i) { serializer(format).load(Object.new) }
      assert_logs(/unrecognized/i) { serializer(format).load("") }
    end
  end

  LEGACY_FORMATS.each do |format|
    test "#{format.inspect} serializer can compress entries" do
      compressed = serializer(format).dump_compressed(@entry, 1)
      uncompressed = serializer(format).dump_compressed(@entry, 100_000)

      assert_operator compressed.bytesize, :<, uncompressed.bytesize
      assert_entry @entry, serializer(format).load(compressed)
      assert_entry @entry, serializer(format).load(uncompressed)

      unless format == :passthrough
        assert_raises ActiveSupport::Cache::DeserializationError do
          serializer(format).load(compressed.byteslice(0..-4))
        end
      end
    end
  end

  test ":message_pack serializer handles missing class gracefully" do
    klass = Class.new do
      def self.name; "DoesNotActuallyExist"; end
      def self.from_msgpack_ext(string); self.new; end
      def to_msgpack_ext; ""; end
    end

    dumped = serializer(:message_pack).dump(klass.new)
    assert_not_nil dumped
    assert_nil serializer(:message_pack).load(dumped)
  end

  test "loads message pack dependency when constant is missing" do
    message_pack = ActiveSupport.send(:remove_const, :MessagePack) if defined?(ActiveSupport::MessagePack)

    assert_same serializer(:message_pack), ActiveSupport::Cache::SerializerWithFallback[:message_pack]
  ensure
    ActiveSupport.const_set(:MessagePack, message_pack) if message_pack
  end

  test "marshal 7.0 compression keeps uncompressed payload when compression is not smaller" do
    entry = ActiveSupport::Cache::Entry.new(Random.bytes(64))
    dumped = serializer(:marshal_7_0).dump_compressed(entry, 1)

    assert serializer(:marshal_7_0).send(:dumped?, dumped)
    assert_entry entry, serializer(:marshal_7_0).load(dumped)
  end

  test "raises deserialization error for invalid marshal payload" do
    assert_raises ActiveSupport::Cache::DeserializationError do
      serializer(:marshal_7_1).load("\x04\x08".b)
    end
  end

  test "message pack availability is false when dependency cannot be loaded" do
    message_pack = ActiveSupport.send(:remove_const, :MessagePack) if defined?(ActiveSupport::MessagePack)
    serializer = serializer(:message_pack)
    serializer.remove_instance_variable(:@available) if serializer.instance_variable_defined?(:@available)

    serializer.stub(:require, ->(*) { raise LoadError }) do
      assert_not serializer.send(:available?)
    end
  ensure
    ActiveSupport.const_set(:MessagePack, message_pack) if message_pack
    serializer&.remove_instance_variable(:@available) if serializer&.instance_variable_defined?(:@available)
  end

  test "raises on invalid format name" do
    assert_raises KeyError do
      ActiveSupport::Cache::SerializerWithFallback[:invalid_format]
    end
  end

  private
    def serializer(format)
      ActiveSupport::Cache::SerializerWithFallback[format]
    end

    def assert_entry(expected, actual)
      assert_equal \
        [expected.value, expected.version, expected.expires_at],
        [actual.value, actual.version, actual.expires_at]
    end

    def assert_logs(pattern, &block)
      io = StringIO.new
      ActiveSupport::Cache::Store.with(logger: Logger.new(io), &block)
      assert_match pattern, io.string
    end
end
