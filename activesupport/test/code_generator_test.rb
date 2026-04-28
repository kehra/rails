# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/code_generator"

class CodeGeneratorTest < ActiveSupport::TestCase
  def test_batch_defines_methods_and_returns_block_result
    owner = Class.new
    namespace = Object.new

    result = ActiveSupport::CodeGenerator.batch(owner, __FILE__, __LINE__) do |generator|
      ActiveSupport::CodeGenerator.batch(generator, __FILE__, __LINE__) do |same_generator|
        assert_same generator, same_generator
      end

      generator.class_eval do |sources|
        sources << "def generated_method; :generated; end"
      end

      generator.define_cached_method(:cached_method, namespace: namespace) do |sources|
        sources << "def cached_method; :cached; end"
      end
      generator.define_cached_method(:cached_method, namespace: namespace, as: :cached_alias) do
        raise "canonical cached method should only be generated once per batch"
      end
      generator.define_cached_method(:cached_method, namespace: namespace, as: :cached_alias) do
        raise "alias should be fetched from the current method map"
      end

      :result
    end

    instance = owner.new
    assert_equal :result, result
    assert_equal :generated, instance.generated_method
    assert_equal :cached, instance.cached_method
    assert_equal :cached, instance.cached_alias

    second_owner = Class.new
    ActiveSupport::CodeGenerator.batch(second_owner, __FILE__, __LINE__) do |generator|
      generator.define_cached_method(:cached_method, namespace: namespace) do
        raise "cached method should be reused without new source"
      end
    end

    assert_equal :cached, second_owner.new.cached_method
  end
end
