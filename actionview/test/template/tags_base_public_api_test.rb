# frozen_string_literal: true

require "abstract_unit"
require "action_view/helpers/tags"
require "action_view/helpers/tags/base"

class TagsBasePublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::FormHelper

  class ProbeTag < ActionView::Helpers::Tags::Base
    def object_name
      @object_name
    end

    def method_name
      @method_name
    end

    def generate_indexed_names?
      @generate_indexed_names
    end

    def auto_index
      @auto_index
    end

    def value_for_test
      value
    end

    def add_name_and_id(options, value = nil)
      add_default_name_and_field_for_value(value, options)
    end
  end

  class ParamObject
    def initialize(param = "7")
      @param = param
    end

    def to_param
      @param
    end

    def title
      "Title"
    end
  end

  test "tags module exposes eager autoloaded tag classes" do
    assert ActionView::Helpers::Tags.const_defined?(:CheckBox)
    assert ActionView::Helpers::Tags.const_defined?(:WeekdaySelect)
    assert_equal ActionView::Helpers::Tags::Base, ActionView::Helpers::Tags.const_get(:Base)
  end

  test "base initializes names objects and default id state" do
    tag = ProbeTag.new("post", "title", self, object: ParamObject.new, skip_default_ids: false)

    assert_equal "post", tag.object_name
    assert_equal "title", tag.method_name
    assert_equal "Title", tag.value_for_test
    assert_not tag.generate_indexed_names?
    assert_nil tag.auto_index
  end

  test "base initializes indexed object names from object param" do
    tag = ProbeTag.new("post[]", "title", self, object: ParamObject.new("abc"))

    assert_equal "post", tag.object_name
    assert tag.generate_indexed_names?
    assert_equal "abc", tag.auto_index
  end

  test "base initializes indexed object names from instance variable" do
    @comment = ParamObject.new("iv")

    tag = ProbeTag.new("comment[]", "title", self, {})

    assert_equal "iv", tag.auto_index
  end

  test "base render must be implemented by subclasses" do
    tag = ActionView::Helpers::Tags::Base.new("post", "title", self, object: ParamObject.new)

    error = assert_raises(NotImplementedError) { tag.render }
    assert_equal "Subclasses must implement a render method", error.message
  end

  test "base retrieves nil object for nested object name without raising" do
    tag = ProbeTag.new("post[author]", "name", self, {})

    assert_nil tag.object
  end

  test "base rejects indexed object name when object param and instance variable are absent" do
    error = assert_raises(ArgumentError) do
      ProbeTag.new("missing[]", "title", self, {})
    end

    assert_match "object[] naming", error.message
  end

  test "base respects method names outside object option" do
    tag = ProbeTag.new("post", "missing", self, object: ParamObject.new, allow_method_names_outside_object: true)
    assert_nil tag.value_for_test

    tag = ProbeTag.new("post", "title", self, object: ParamObject.new, allow_method_names_outside_object: true)
    assert_equal "Title", tag.value_for_test
  end

  test "base default name and id handles value suffix namespace and blank index" do
    tag = ProbeTag.new("post[]", "category?", self, object: ParamObject.new(""))
    options = { "namespace" => "admin" }

    tag.add_name_and_id(options, "News.Today!")

    assert_equal "post[][category]", options["name"]
    assert_equal "admin_post__category_news_today", options["id"]
  end

  test "base default name respects skipped ids and namespace fallback" do
    tag = ProbeTag.new("post", "title", self, object: ParamObject.new, skip_default_ids: true)
    options = { "namespace" => "admin" }

    tag.add_name_and_id(options)

    assert_equal "post[title]", options["name"]
    assert_nil options["id"]

    tag = ProbeTag.new("post", "title", self, object: ParamObject.new)
    options = { "id" => nil, "namespace" => "admin" }

    tag.add_name_and_id(options)

    assert_equal "admin", options["id"]
  end
end
