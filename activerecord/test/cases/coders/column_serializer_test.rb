# frozen_string_literal: true

require "cases/helper"
require "active_record/coders/column_serializer"

class ColumnSerializerTest < ActiveRecord::TestCase
  class ArrayCoder
    def dump(object)
      object.join(",")
    end

    def load(payload)
      payload&.split(",")
    end
  end

  class NilCoder
    def dump(object)
      object
    end

    def load(_payload)
      nil
    end
  end

  class RequiredArgument
    def initialize(argument)
      @argument = argument
    end
  end

  def test_dump_serializes_valid_objects_and_skips_nil
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new, Array)

    assert_equal "red,blue", serializer.dump(["red", "blue"])
    assert_nil serializer.dump(nil)
  end

  def test_load_deserializes_valid_payloads
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new, Array)

    assert_equal ["red", "blue"], serializer.load("red,blue")
  end

  def test_load_nil_returns_new_object_for_constrained_class
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new, Array)

    assert_equal [], serializer.load(nil)
  end

  def test_load_nil_returns_nil_for_object_class
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new)

    assert_nil serializer.load(nil)
  end

  def test_load_builds_new_object_when_coder_returns_nil_for_constrained_class
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", NilCoder.new, Array)

    assert_equal [], serializer.load("ignored")
  end

  def test_load_returns_nil_when_coder_returns_nil_for_object_class
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", NilCoder.new)

    assert_nil serializer.load("ignored")
  end

  def test_assert_valid_value_accepts_nil_and_matching_type
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new, Array)

    assert_nil serializer.assert_valid_value(nil, action: "dump")
    assert_nil serializer.assert_valid_value([], action: "dump")
  end

  def test_assert_valid_value_rejects_wrong_dump_type
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new, Array)

    error = assert_raises(ActiveRecord::SerializationTypeMismatch) do
      serializer.dump("wrong")
    end

    assert_match "can't dump `tags`: was supposed to be a Array, but was a String", error.message
    assert_match "-- \"wrong\"", error.message
  end

  def test_assert_valid_value_rejects_wrong_load_type
    serializer = ActiveRecord::Coders::ColumnSerializer.new("tags", ArrayCoder.new, Hash)

    error = assert_raises(ActiveRecord::SerializationTypeMismatch) do
      serializer.load("red,blue")
    end

    assert_match "can't load `tags`: was supposed to be a Hash, but was a Array", error.message
  end

  def test_init_with_restores_serialized_state
    serializer = ActiveRecord::Coders::ColumnSerializer.allocate
    serializer.init_with("attr_name" => "tags", "object_class" => Array, "coder" => ArrayCoder.new)

    assert_equal Array, serializer.object_class
    assert_instance_of ArrayCoder, serializer.coder
    assert_equal ["red", "blue"], serializer.load("red,blue")
  end

  def test_initialize_rejects_classes_without_zero_argument_constructor
    error = assert_raises(ArgumentError) do
      ActiveRecord::Coders::ColumnSerializer.new("tags", NilCoder.new, RequiredArgument)
    end

    assert_equal "Cannot serialize ColumnSerializerTest::RequiredArgument. Classes passed to `serialize` must have a 0 argument constructor.", error.message
  end
end
