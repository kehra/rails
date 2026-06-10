# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/delegation"
require "active_support/core_ext/module/delegation"

class DelegationTest < ActiveSupport::TestCase
  class DelegateTarget
    def no_arguments = :no_arguments
    def required(argument) = [:required, argument]
    def keyword(required:) = [:keyword, required]
    def block_with_ampersand(&) = yield(:ampersand)
    def block_with_name(&block) = block.call(:named)
    def optional(argument = :default) = [:optional, argument]
    def [](key) = [:brackets, key]

    protected
      def protected_method = :protected_method
  end

  def test_class_delegator_initializes_and_updates_target
    delegator = ActiveSupport::Delegation::ClassDelegator.new("first")
    assert_equal "first", delegator.__getobj__

    delegator.__setobj__("second")
    assert_equal "second", delegator.__getobj__
  end

  def test_class_delegator_cannot_delegate_to_self
    delegator = ActiveSupport::Delegation::ClassDelegator.new("first")

    assert_raises(ArgumentError, match: /cannot delegate to self/) do
      delegator.__setobj__(delegator)
    end
  end

  def test_delegate_class_generates_forwarders_and_evaluates_block
    delegate_class = ActiveSupport::Delegation.DelegateClass(DelegateTarget) do
      def marker = :marker
    end
    delegator = delegate_class.new(DelegateTarget.new)

    assert_equal :marker, delegator.marker
    assert_equal :no_arguments, delegator.no_arguments
    assert_equal [:required, :value], delegator.required(:value)
    assert_equal [:keyword, :value], delegator.keyword(required: :value)
    assert_equal :ampersand, delegator.block_with_ampersand { |value| value }
    assert_equal :named, delegator.block_with_name { |value| value }
    assert_equal [:optional, :default], delegator.optional
    assert_equal [:optional, :value], delegator.optional(:value)
    assert_equal [:brackets, :key], delegator[:key]
    assert_raises(NoMethodError) { delegator.send(:protected_method) }
  end

  def test_generate_with_explicit_signature
    owner = Module.new
    ActiveSupport::Delegation.generate(owner, [:call], to: :target, signature: "value")
    klass = Class.new do
      include owner
      def target = ->(value) { [:called, value] }
    end

    assert_equal [:called, :value], klass.new.call(:value)
  end

  def test_generate_with_explicit_receiver_raises_for_missing_methods
    assert_raises(NameError) do
      ActiveSupport::Delegation.generate(Module.new, [:missing], to: :target, as: String)
    end
  end

  def test_generate_with_module_receiver_falls_back_for_missing_methods
    owner = Module.new
    ActiveSupport::Delegation.generate(owner, [:missing], to: String)
    String.define_singleton_method(:missing) { |*arguments| [:missing, arguments] }
    klass = Class.new { include owner }

    assert_equal [:missing, [:value]], klass.new.missing(:value)
  ensure
    String.singleton_class.remove_method(:missing) if String.respond_to?(:missing)
  end

  class WeirdParameterTarget
    def weird(argument = :default) = argument
  end

  def test_delegate_class_handles_unexpected_parameter_metadata
    fake_parameters = Object.new
    def fake_parameters.empty? = false
    def fake_parameters.all? = true
    def fake_parameters.map
      [yield(:unknown, :argument)]
    end

    patch = Module.new do
      define_method(:parameters) do
        if owner == WeirdParameterTarget && name == :weird
          fake_parameters
        else
          super()
        end
      end
    end

    UnboundMethod.prepend(patch)
    delegate_class = ActiveSupport::Delegation.DelegateClass(WeirdParameterTarget)

    assert_equal :default, delegate_class.new(WeirdParameterTarget.new).weird
  end

  def test_delegate_class_without_block
    delegate_class = ActiveSupport::Delegation.DelegateClass(DelegateTarget)

    assert_equal :no_arguments, delegate_class.new(DelegateTarget.new).no_arguments
  end

  class Target
    def each_doubled
      yield 1
      yield 2
    end

    def maybe_yield
      yield :yielded if block_given?
      :returned
    end

    def with_required(arg)
      yield arg
    end

    def with_keyword(value:)
      yield value
    end
  end

  DelegatingWrapper = ActiveSupport::Delegation.DelegateClass(Target)

  setup do
    @wrapper = DelegatingWrapper.new(Target.new)
  end

  test "forwards a block to a delegated method that yields implicitly" do
    collected = []
    @wrapper.each_doubled { |value| collected << value }
    assert_equal [1, 2], collected
  end

  test "block_given? is true in the delegated method when a block is passed" do
    assert_equal :yielded, (@wrapper.maybe_yield { |v| break v })
  end

  test "no block is forwarded when none is given" do
    assert_equal :returned, @wrapper.maybe_yield
  end

  test "forwards a block alongside a required positional argument" do
    assert_equal 42, (@wrapper.with_required(42) { |arg| break arg })
  end

  test "forwards a block alongside a required keyword argument" do
    assert_equal :ok, (@wrapper.with_keyword(value: :ok) { |v| break v })
  end

  test "forwards a block to a yielding method inherited from the delegated class" do
    wrapper = ActiveSupport::Delegation.DelegateClass(Array).new([1, 2, 3])
    assert_equal [2, 4, 6], wrapper.map { |n| n * 2 }
    assert_equal [1, 3], wrapper.select(&:odd?)
  end
end
