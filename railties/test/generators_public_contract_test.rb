# frozen_string_literal: true

require "abstract_unit"
require "rails/generators"

class GeneratorsPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_options = Rails::Generators.instance_variable_get(:@options)
    @original_hidden_namespaces = Rails::Generators.instance_variable_get(:@hidden_namespaces)
    @original_after_generate_callbacks = Rails::Generators.instance_variable_get(:@after_generate_callbacks)
    @original_generated_files = Rails::Generators.class_variable_get(:@@generated_files) if Rails::Generators.class_variable_defined?(:@@generated_files)
  end

  teardown do
    restore_instance_variable(:@options, @original_options)
    restore_instance_variable(:@hidden_namespaces, @original_hidden_namespaces)
    restore_instance_variable(:@after_generate_callbacks, @original_after_generate_callbacks)
    if defined?(@original_generated_files)
      Rails::Generators.class_variable_set(:@@generated_files, @original_generated_files)
    elsif Rails::Generators.class_variable_defined?(:@@generated_files)
      Rails::Generators.remove_class_variable(:@@generated_files)
    end
  end

  test "api only hides browser namespaces and updates generator defaults" do
    Rails::Generators.instance_variable_set(:@options, Marshal.load(Marshal.dump(Rails::Generators::DEFAULT_OPTIONS)))
    Rails::Generators.instance_variable_set(:@hidden_namespaces, [])

    Rails::Generators.api_only!

    assert_includes Rails::Generators.hidden_namespaces, "assets"
    assert_includes Rails::Generators.hidden_namespaces, "helper"
    assert_includes Rails::Generators.hidden_namespaces, "css"
    assert_includes Rails::Generators.hidden_namespaces, "js"
    assert_equal true, Rails::Generators.options[:rails][:api]
    assert_equal false, Rails::Generators.options[:rails][:assets]
    assert_equal false, Rails::Generators.options[:rails][:helper]
    assert_nil Rails::Generators.options[:rails][:template_engine]
    assert_equal :erb, Rails::Generators.options[:mailer][:template_engine]
  end

  test "hidden namespaces handles configured and non test unit frameworks" do
    Rails::Generators.instance_variable_set(:@options, Marshal.load(Marshal.dump(Rails::Generators::DEFAULT_OPTIONS)))
    Rails::Generators.options[:rails][:test_framework] = :test_unit
    Rails::Generators.instance_variable_set(:@hidden_namespaces, nil)

    assert_not_includes Rails::Generators.hidden_namespaces, "test_unit"

    Rails::Generators.options[:rails][:test_framework] = :rspec
    Rails::Generators.instance_variable_set(:@hidden_namespaces, nil)

    assert_includes Rails::Generators.hidden_namespaces, "test_unit"
  end

  test "invoke appends help for generators with required arguments and runs callbacks" do
    generator = Class.new do
      class << self
        attr_reader :started_with
        def namespace = "sample:required"
        def arguments = [Struct.new(:required?).new(true)]
        def start(args, config) = @started_with = [args.dup, config]
      end
    end
    callback_files = nil
    Rails::Generators.class_variable_set(:@@generated_files, [])
    Rails::Generators.after_generate_callbacks << ->(files) { callback_files = files.dup }
    Rails::Generators.add_generated_file("app/models/user.rb")

    with_singleton_method(Rails::Generators, :find_by_namespace, ->(_name, _base = nil, _context = nil) { generator }) do
      Rails::Generators.invoke("sample:required", [], behavior: :invoke)
    end

    assert_equal [["--help"], { behavior: :invoke }], generator.started_with
    assert_equal ["app/models/user.rb"], callback_files
    assert_equal [], Rails::Generators.class_variable_get(:@@generated_files)
  end

  private
    def restore_instance_variable(name, value)
      if value.nil?
        Rails::Generators.remove_instance_variable(name) if Rails::Generators.instance_variable_defined?(name)
      else
        Rails::Generators.instance_variable_set(name, value)
      end
    end

    def with_singleton_method(object, name, replacement)
      singleton = class << object; self; end
      original = object.method(name) if object.respond_to?(name)
      had_own_method = singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.send(:remove_method, name) if had_own_method
      singleton.define_method(name, replacement)
      yield
    ensure
      singleton.send(:remove_method, name) if singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if original && had_own_method
    end
end
