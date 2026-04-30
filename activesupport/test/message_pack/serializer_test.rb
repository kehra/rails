# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/message_pack"
require_relative "shared_serializer_tests"

class MessagePackSerializerTest < ActiveSupport::TestCase
  include MessagePackSharedSerializerTests

  test "raises friendly error when dumping an unsupported object" do
    assert_raises ActiveSupport::MessagePack::UnserializableObjectError do
      dump(UnsupportedObject.new)
    end
  end

  test "raises invalid format for unknown unregistered object loader" do
    unpacker = Object.new
    def unpacker.read
      :unknown_loader
    end

    assert_raises RuntimeError, match: /Invalid format/ do
      ActiveSupport::MessagePack::Extensions.read_object(unpacker)
    end
  end

  test "reraises nested constant lookup errors" do
    assert_raises NameError do
      ActiveSupport::MessagePack::Extensions.load_class("MessagePackSerializerTest::NoSuch::Nested")
    end
  end

  test "raises on invalid serialization signature" do
    assert_raises RuntimeError, match: /Invalid serialization format/ do
      load("not message pack")
    end
  end

  test "can replace the MessagePack factory" do
    original_factory = serializer.message_pack_factory
    frozen_factory = ::MessagePack::Factory.new.freeze

    serializer.message_pack_factory = frozen_factory

    assert_same frozen_factory, serializer.message_pack_factory
    assert_nothing_raised { serializer.warmup }
  ensure
    serializer.message_pack_factory = original_factory
  end

  private
    def serializer
      ActiveSupport::MessagePack
    end

    class UnsupportedObject; end
end
