# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/http/rack_cache"

class RackCacheMetaStoreTest < ActiveSupport::TestCase
  class ReadWriteHash < ::Hash
    alias :read  :[]
    alias :write :[]=

    def exist?(key)
      key?(key)
    end
  end

  setup do
    @backend = ReadWriteHash.new
    @store = ActionDispatch::RailsMetaStore.new(@backend)
  end

  test "resolve returns a store instance" do
    with_rails_cache(@backend) do
      assert_instance_of ActionDispatch::RailsMetaStore, ActionDispatch::RailsMetaStore.resolve(nil)
    end
  end

  test "missing entries read as an empty list" do
    assert_equal [], @store.read(:missing)
  end

  test "stuff is deep duped" do
    @store.write(:foo, bar: :original)
    hash = @store.read(:foo)
    hash[:bar] = :changed
    hash = @store.read(:foo)
    assert_equal :original, hash[:bar]
  end
end

class RackCacheEntityStoreTest < ActiveSupport::TestCase
  setup do
    @backend = RackCacheMetaStoreTest::ReadWriteHash.new
    @store = ActionDispatch::RailsEntityStore.new(@backend)
  end

  test "resolve returns a store instance" do
    with_rails_cache(@backend) do
      assert_instance_of ActionDispatch::RailsEntityStore, ActionDispatch::RailsEntityStore.resolve(nil)
    end
  end

  test "exist delegates to the backing cache" do
    @backend.write("key", ["body"])

    assert @store.exist?("key")
    assert_not @store.exist?("missing")
  end

  test "open and read return cached entity body" do
    @backend.write("key", ["hello", " ", "world"])

    assert_equal ["hello", " ", "world"], @store.open("key")
    assert_equal "hello world", @store.read("key")
    assert_nil @store.read("missing")
  end

  test "write stores body chunks and returns key and size" do
    key, size = @store.write(["hello", " ", "world"])

    assert_equal 11, size
    assert_equal ["hello", " ", "world"], @backend.read(key)
    assert_equal "hello world", @store.read(key)
  end
end

private
  def with_rails_cache(cache)
    had_cache = Rails.respond_to?(:cache)
    original_cache = Rails.cache if had_cache
    Rails.define_singleton_method(:cache) { cache }
    yield
  ensure
    if had_cache
      Rails.define_singleton_method(:cache) { original_cache }
    else
      Rails.singleton_class.remove_method(:cache)
    end
  end
