# frozen_string_literal: true

require "abstract_unit"

class TemplateErrorTest < ActiveSupport::TestCase
  def test_provides_original_message
    error = begin
      raise Exception.new("original")
    rescue Exception
      raise ActionView::Template::Error.new("test") rescue $!
    end

    assert_equal "original", error.message
  end

  def test_provides_original_backtrace
    error = begin
      original_exception = Exception.new
      original_exception.set_backtrace(%W[ foo bar baz ])
      raise original_exception
    rescue Exception
      raise ActionView::Template::Error.new("test") rescue $!
    end

    assert_equal %W[ foo bar baz ], error.backtrace
  end

  def test_provides_useful_inspect
    error = begin
      raise Exception.new("original")
    rescue Exception
      raise ActionView::Template::Error.new("test") rescue $!
    end

    assert_equal "#<ActionView::Template::Error: original>", error.inspect
  end

  def test_annotated_source_code_returns_empty_array_if_source_cant_be_found
    template = Class.new do
      def identifier
        "something"
      end
    end.new

    error = begin
      raise
    rescue
      raise ActionView::Template::Error.new(template) rescue $!
    end

    assert_equal [], error.annotated_source_code
  end
end

class MissingTemplatePublicContractTest < ActiveSupport::TestCase
  TemplatePath = Struct.new(:prefix, :basename, :partial) do
    def partial? = partial
    def to_s = File.join(prefix, basename)
  end

  class Resolver
    def initialize(paths)
      @paths = paths
    end

    def all_template_paths
      @paths
    end

    def to_s
      "resolver"
    end
  end

  test "initialize describes missing layouts" do
    error = ActionView::MissingTemplate.new(["/views"], "layouts/missing", [], false, { formats: [:html] })

    assert_equal "layouts/missing", error.path
    assert_match "Missing layout", error.message
  end

  test "corrections compares candidate prefixes even when requested prefix has no exact directory" do
    resolver = Resolver.new([
      TemplatePath.new("customers", "show.html.erb", false),
      TemplatePath.new("admin/customers", "edit.html.erb", false)
    ])
    error = ActionView::MissingTemplate.new([resolver], "shof", ["missing_prefix"], false, { formats: [:html] })

    assert_includes error.corrections, "customers/show.html.erb"
  end

  test "results keeps only the best sized entries in score order" do
    results = ActionView::MissingTemplate::Results.new(2)

    assert results.should_record?(0.2)
    results.add("third", 0.3)
    results.add("first", 0.1)
    results.add("second", 0.2)
    results.add("ignored", 0.5)

    assert_equal ["first", "second"], results.to_a
    assert_not results.should_record?(0.6)
  end
end
