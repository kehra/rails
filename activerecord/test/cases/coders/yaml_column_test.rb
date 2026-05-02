# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  module Coders
    class YAMLColumnTest < ActiveRecord::TestCase
      setup do
        @use_yaml_unsafe_load = ActiveRecord.use_yaml_unsafe_load
        ActiveRecord.use_yaml_unsafe_load = true
      end

      teardown do
        ActiveRecord.use_yaml_unsafe_load = @use_yaml_unsafe_load
      end

      def test_initialize_takes_class
        coder = YAMLColumn.new("attr_name", Object)
        assert_equal Object, coder.object_class
      end

      def test_type_mismatch_on_different_classes_on_dump
        coder = YAMLColumn.new("tags", Array)
        error = assert_raises(SerializationTypeMismatch) do
          coder.dump("a")
        end
        assert_equal %{can't dump `tags`: was supposed to be a Array, but was a String. -- "a"}, error.to_s
      end

      def test_type_mismatch_on_different_classes
        coder = YAMLColumn.new("tags", Array)
        error = assert_raises(SerializationTypeMismatch) do
          coder.load "--- foo"
        end
        assert_equal %{can't load `tags`: was supposed to be a Array, but was a String. -- "foo"}, error.to_s
      end

      def test_nil_is_ok
        coder = YAMLColumn.new("attr_name")
        assert_nil coder.load "--- "
      end

      def test_returns_new_with_different_class
        coder = YAMLColumn.new("attr_name", SerializationTypeMismatch)
        assert_equal SerializationTypeMismatch, coder.load("--- ").class
      end

      def test_returns_string_unless_starts_with_dash
        coder = YAMLColumn.new("attr_name")
        assert_equal "foo", coder.load("foo")
      end

      def test_load_raises_on_other_classes
        coder = YAMLColumn.new("attr_name")
        assert_raises TypeError do
          coder.load([])
        end
      end

      def test_load_doesnt_swallow_yaml_exceptions
        coder = YAMLColumn.new("attr_name")
        bad_yaml = "--- {"
        assert_raises(Psych::SyntaxError) do
          coder.load(bad_yaml)
        end
      end

      def test_load_doesnt_handle_undefined_class_or_module
        coder = YAMLColumn.new("attr_name")
        missing_class_yaml = '--- !ruby/object:DoesNotExistAndShouldntEver {}\n'
        assert_raises(ArgumentError) do
          coder.load(missing_class_yaml)
        end
      end

      def test_dump_uses_unsafe_load_configuration
        coder = YAMLColumn.new("attr_name")

        assert_match "--- :somesymbol", coder.dump(:somesymbol)
      end

      def test_init_with_builds_safe_coder_for_legacy_payload
        coder = YAMLColumn.allocate
        coder.init_with("attr_name" => "attr_name", "object_class" => Object, "permitted_classes" => [Time], "unsafe_load" => true)

        assert_instance_of YAMLColumn::SafeCoder, coder.coder
        assert_kind_of Time, coder.load(YAML.dump(Time.now))
      end

      def test_init_with_preserves_existing_coder
        existing_coder = YAMLColumn::SafeCoder.new(unsafe_load: true)
        coder = YAMLColumn.allocate
        coder.init_with("attr_name" => "attr_name", "object_class" => Object, "coder" => existing_coder)

        assert_same existing_coder, coder.coder
      end

      def test_coder_builds_legacy_safe_coder_from_instance_variables
        coder = YAMLColumn.allocate
        coder.instance_variable_set(:@attr_name, "attr_name")
        coder.instance_variable_set(:@object_class, Object)
        coder.instance_variable_set(:@permitted_classes, [Symbol])
        coder.instance_variable_set(:@unsafe_load, nil)

        assert_instance_of YAMLColumn::SafeCoder, coder.coder
        assert_equal :somesymbol, coder.load(YAML.dump(:somesymbol))
      end

      def test_coder_builds_default_legacy_safe_coder_without_instance_variables
        coder = YAMLColumn.allocate

        assert_instance_of YAMLColumn::SafeCoder, coder.coder
      end

      class RequiredArgument
        def initialize(argument)
          @argument = argument
        end
      end

      def test_initialize_rejects_classes_without_zero_argument_constructor
        error = assert_raises(ArgumentError) do
          YAMLColumn.new("attr_name", RequiredArgument)
        end

        assert_equal "Cannot serialize ActiveRecord::Coders::YAMLColumnTest::RequiredArgument. Classes passed to `serialize` must have a 0 argument constructor.", error.message
      end
    end

    class YAMLColumnTestWithSafeLoad < YAMLColumnTest
      setup do
        @use_yaml_unsafe_load = ActiveRecord.use_yaml_unsafe_load
        @yaml_column_permitted_classes_default = ActiveRecord.yaml_column_permitted_classes
        ActiveRecord.use_yaml_unsafe_load = false
      end

      teardown do
        ActiveRecord.use_yaml_unsafe_load = @use_yaml_unsafe_load
        ActiveRecord.yaml_column_permitted_classes = @yaml_column_permitted_classes_default
      end

      def test_yaml_column_permitted_classes_are_consumed_by_safe_load
        ActiveRecord.yaml_column_permitted_classes = [Symbol, Time]

        coder = YAMLColumn.new("attr_name")
        time_yaml = YAML.dump(Time.new)
        symbol_yaml = YAML.dump(:somesymbol)

        assert_nothing_raised do
          coder.load(time_yaml)
          coder.load(symbol_yaml)
        end
      end

      def test_yaml_column_permitted_classes_are_consumed_by_safe_dump
        if Gem::Version.new(Psych::VERSION) < Gem::Version.new("5.1")
          skip "YAML.safe_dump is either missing on unavailable on #{Psych::VERSION}"
        end

        coder = YAMLColumn.new("attr_name")
        assert_raises(Psych::DisallowedClass) do
          coder.dump([Time.new])
        end
      end

      def test_yaml_column_permitted_classes_option
        ActiveRecord.yaml_column_permitted_classes = [Symbol]

        coder = YAMLColumn.new("attr_name", permitted_classes: [Time])
        time_yaml = YAML.dump(Time.new)
        symbol_yaml = YAML.dump(:somesymbol)

        assert_nothing_raised do
          coder.load(time_yaml)
          coder.load(symbol_yaml)
        end
      end

      def test_yaml_column_unsafe_load_option
        ActiveRecord.use_yaml_unsafe_load = false
        ActiveRecord.yaml_column_permitted_classes = []

        coder = YAMLColumn.new("attr_name", unsafe_load: true)
        time_yaml = YAML.dump(Time.new)
        symbol_yaml = YAML.dump(:somesymbol)

        assert_nothing_raised do
          coder.load(time_yaml)
          coder.load(symbol_yaml)
        end
      end

      def test_yaml_column_override_unsafe_load_option
        ActiveRecord.use_yaml_unsafe_load = true
        ActiveRecord.yaml_column_permitted_classes = []

        coder = YAMLColumn.new("attr_name", unsafe_load: false)
        time_yaml = YAML.dump(Time.new)

        assert_raises(Psych::DisallowedClass) do
          coder.load(time_yaml)
        end
      end

      def test_yaml_column_override_unsafe_dump_option
        ActiveRecord.use_yaml_unsafe_load = true
        ActiveRecord.yaml_column_permitted_classes = []

        coder = YAMLColumn.new("attr_name", unsafe_load: false)

        assert_equal YAML.safe_dump("safe", aliases: true), coder.dump("safe")
      end

      def test_load_doesnt_handle_undefined_class_or_module
        coder = YAMLColumn.new("attr_name")
        missing_class_yaml = '--- !ruby/object:DoesNotExistAndShouldntEver {}\n'
        assert_raises(Psych::DisallowedClass) do
          coder.load(missing_class_yaml)
        end
      end
    end
  end
end
