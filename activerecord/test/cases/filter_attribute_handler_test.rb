# frozen_string_literal: true

require "cases/helper"
require "active_record/filter_attribute_handler"
require "models/book"

class FilterAttributeHandlerTest < ActiveRecord::TestCase
  setup do
    @previous_listeners = ActiveRecord::FilterAttributeHandler.instance_variable_get(:@sensitive_attribute_declaration_listeners)
    ActiveRecord::FilterAttributeHandler.remove_instance_variable(:@sensitive_attribute_declaration_listeners) if @previous_listeners
  end

  teardown do
    if @previous_listeners
      ActiveRecord::FilterAttributeHandler.instance_variable_set(:@sensitive_attribute_declaration_listeners, @previous_listeners)
    elsif ActiveRecord::FilterAttributeHandler.instance_variable_defined?(:@sensitive_attribute_declaration_listeners)
      ActiveRecord::FilterAttributeHandler.remove_instance_variable(:@sensitive_attribute_declaration_listeners)
    end
  end

  def test_enable_applies_collected_attributes_and_future_declarations
    app = application_with_filter_parameters([])
    handler = ActiveRecord::FilterAttributeHandler.new(app)
    klass = Class.new(Book) do
      def self.name = "SpecialBook"
    end

    handler.send(:install_collecting_hook)
    ActiveRecord::FilterAttributeHandler.sensitive_attribute_was_declared(klass, [:secret])
    assert_empty app.config.filter_parameters

    handler.enable
    assert_equal ["special_book.secret"], app.config.filter_parameters

    ActiveRecord::FilterAttributeHandler.sensitive_attribute_was_declared(klass, [:token])
    assert_equal ["special_book.secret", "special_book.token"], app.config.filter_parameters
  end

  def test_enable_keeps_duplicate_filters_once
    app = application_with_filter_parameters(["special_book.secret"])
    handler = ActiveRecord::FilterAttributeHandler.new(app)
    klass = Class.new(Book) do
      def self.name = "SpecialBook"
    end

    handler.enable
    ActiveRecord::FilterAttributeHandler.sensitive_attribute_was_declared(klass, [:secret])

    assert_equal ["special_book.secret"], app.config.filter_parameters
  end

  def test_base_and_abstract_classes_are_ignored
    app = application_with_filter_parameters([])
    handler = ActiveRecord::FilterAttributeHandler.new(app)
    abstract_class = Class.new(ActiveRecord::Base) do
      self.abstract_class = true
      def self.name = "AbstractSecret"
    end

    handler.enable
    ActiveRecord::FilterAttributeHandler.sensitive_attribute_was_declared(ActiveRecord::Base, [:secret])
    ActiveRecord::FilterAttributeHandler.sensitive_attribute_was_declared(abstract_class, [:secret])

    assert_empty app.config.filter_parameters
  end

  def test_anonymous_classes_use_unqualified_attribute_filter
    app = application_with_filter_parameters([])
    handler = ActiveRecord::FilterAttributeHandler.new(app)
    anonymous_class = Class.new(Book)

    handler.enable
    ActiveRecord::FilterAttributeHandler.sensitive_attribute_was_declared(anonymous_class, [:secret])

    assert_equal ["secret"], app.config.filter_parameters
  end

  private
    def application_with_filter_parameters(parameters)
      Struct.new(:config).new(Struct.new(:filter_parameters).new(parameters))
    end
end
