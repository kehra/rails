# frozen_string_literal: true

require "abstract_unit"
require "controller/fake_models"

class FormBuilderPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::FormHelper

  test "form builder exposes model partial path and form id" do
    builder = ActionView::Helpers::FormBuilder.new("post", Post.new, self, id: "options-id", html: { id: "html-id" })

    assert_same builder, builder.to_model
    assert_equal "form", builder.to_partial_path
    assert_equal "form", ActionView::Helpers::FormBuilder._to_partial_path
    assert_equal "html-id", builder.id
  end

  test "form builder fields delegates through fields_for with method names outside object" do
    builder = ActionView::Helpers::FormBuilder.new("post", Post.new, self, {})

    output = builder.fields(:metadata) do |fields|
      concat fields.text_field(:anything)
    end

    assert_includes output, 'name="post[metadata][anything]"'
  end

  test "form builder initialize accepts nil object name" do
    builder = ActionView::Helpers::FormBuilder.new(nil, nil, self, {})

    assert_nil builder.object_name
    assert_nil builder.object
  end

  test "form builder initialize raises for array object name without indexed object" do
    error = assert_raises(ArgumentError) do
      ActionView::Helpers::FormBuilder.new("missing[]", nil, self, {})
    end

    assert_match "object[] naming", error.message
  end

  test "form builder initialize with nil options is invalid after applying defaults" do
    assert_raises(NoMethodError) do
      ActionView::Helpers::FormBuilder.new("post", Post.new, self, nil)
    end
  end
end
