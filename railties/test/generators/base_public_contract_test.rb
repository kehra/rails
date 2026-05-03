# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"
require "minitest/mock"
require "rails/generators"
require "rails/generators/actions"
require "rails/generators/base"

class BaseGeneratorPublicContractTest < ActiveSupport::TestCase
  test "source root can be set explicitly and otherwise falls back to default" do
    generator = Class.new(Rails::Generators::Base) do
      def self.default_source_root = "/default/templates"
    end

    assert_equal "/default/templates", generator.source_root
    assert_equal "/custom/templates", generator.source_root("/custom/templates")
    assert_equal "/custom/templates", generator.source_root
  end

  test "desc accepts explicit text and otherwise reads usage or builds default text" do
    generator = Class.new(Rails::Generators::Base) do
      def self.base_name = "sample"
      def self.generator_name = "widget"
    end

    assert_equal "Explicit description", generator.desc("Explicit description")

    Dir.mktmpdir do |dir|
      usage = File.join(dir, "USAGE")
      File.write(usage, "Usage for <%= generator_name %>")
      generator.stub(:usage_path, usage) do
        generator.remove_instance_variable(:@desc) if generator.instance_variable_defined?(:@desc)
        assert_equal "Usage for widget", generator.desc
      end
    end

    generator.stub(:usage_path, nil) do
      generator.remove_instance_variable(:@desc) if generator.instance_variable_defined?(:@desc)
      assert_equal "Description:\n    Create sample files for widget generator.", generator.desc
    end
  end

  test "namespace accepts explicit names and strips generator suffix from inferred names" do
    generator = Class.new(Rails::Generators::Base)

    assert_equal "admin:reports", generator.namespace("admin:reports")

    Rails::Generators.const_set(:ReportsGenerator, Class.new(Rails::Generators::Base))
    assert_equal "rails:reports", Rails::Generators::ReportsGenerator.namespace
  ensure
    Rails::Generators.send(:remove_const, :ReportsGenerator) if Rails::Generators.const_defined?(:ReportsGenerator, false)
  end

  test "hook_for registers defaults and boolean hooks, and remove_hook_for cleans them" do
    generator = Class.new(Rails::Generators::Base) do
      def self.generator_name = "report"
      def self.base_name = "rails"
    end
    found = Class.new
    lookup = nil

    Rails::Generators.stub(:find_by_namespace, ->(*args) { lookup = args; found }) do
      generator.hook_for :test_framework, default: :minitest
      generator.hook_for :preview, type: :boolean

      assert_equal "NAME", generator.class_options[:test_framework].banner
      assert_nil generator.class_options[:preview].banner
      assert_same found, generator.test_framework_generator
      assert_equal "report", lookup.first
      assert_equal ["rails", "report"], generator.hooks[:test_framework]

      generator.remove_hook_for :test_framework, :preview

      assert_nil generator.hooks[:test_framework]
      assert_nil generator.hooks[:preview]
      assert_raises(NoMethodError) { generator.test_framework_generator }
    end
  end

  test "default source root returns nil when templates directory is missing" do
    generator = Class.new(Rails::Generators::Base) do
      def self.base_name = "missing"
      def self.generator_name = "template"
      def self.default_generator_root = "/definitely/missing/generator/root"
    end

    assert_nil generator.default_source_root
  end
end
