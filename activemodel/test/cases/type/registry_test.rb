# frozen_string_literal: true

require "cases/helper"

module ActiveModel
  module Type
    class RegistryTest < ActiveModel::TestCase
      test "a class can be registered for a symbol" do
        registry = Type::Registry.new
        registry.register(:foo, ::String)
        registry.register(:bar, ::Array)

        assert_equal "", registry.lookup(:foo)
        assert_equal [], registry.lookup(:bar)
        assert_equal [:a, :a], registry.lookup(:bar, 2, :a) # Array.new(2, :a)
        assert_equal [{}, {}], registry.lookup(:bar, 2, {}) # Array.new(2, {})
      end

      test "duplicated registry keeps independent registrations" do
        registry = Type::Registry.new
        registry.register(:foo, ::String)

        duplicated = registry.dup
        duplicated.register(:foo, ::Array)

        assert_equal "", registry.lookup(:foo)
        assert_equal [], duplicated.lookup(:foo)
      end

      test "class registration works when proc ruby2 keywords support is unavailable" do
        original = Proc.instance_method(:respond_to?)
        old_verbose = $VERBOSE
        $VERBOSE = nil
        Proc.define_method(:respond_to?) do |name, include_private = false|
          name == :ruby2_keywords ? false : original.bind_call(self, name, include_private)
        end
        $VERBOSE = old_verbose

        registry = Type::Registry.new
        registry.register(:foo, ::String)

        assert_equal "", registry.lookup(:foo)
      ensure
        $VERBOSE = nil
        Proc.define_method(:respond_to?, original) if original
        $VERBOSE = old_verbose
      end

      test "a block can be registered" do
        registry = Type::Registry.new
        registry.register(:foo) do |type, *args|
          [type, args, "block for foo"]
        end
        registry.register(:bar) do |type, *args|
          [type, args, "block for bar"]
        end
        registry.register(:baz) do |type, **kwargs|
          [type, kwargs, "block for baz"]
        end

        assert_equal [:foo, [1], "block for foo"], registry.lookup(:foo, 1)
        assert_equal [:foo, [2], "block for foo"], registry.lookup(:foo, 2)
        assert_equal [:bar, [1, 2, 3], "block for bar"], registry.lookup(:bar, 1, 2, 3)
        assert_equal [:baz, { kw: 1 }, "block for baz"], registry.lookup(:baz, kw: 1)
      end

      test "a reasonable error is given when no type is found" do
        registry = Type::Registry.new

        e = assert_raises(ArgumentError) do
          registry.lookup(:foo)
        end

        assert_equal "Unknown type :foo", e.message
      end
    end
  end
end
