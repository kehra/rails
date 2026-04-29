# frozen_string_literal: true

require "abstract_unit"

class TagHelperPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::TagHelper

  test "tag helper public APIs handle escaping tokens and cdata" do
    assert_equal "<![CDATA[hello]]]]><![CDATA[>world]]>", cdata_section("hello]]>world")
    assert_equal "1 &lt; 2 &amp; 3", escape_once("1 < 2 &amp; 3")
    assert_equal "foo bar baz", token_list("foo", ["bar", { baz: true, qux: false }])
    assert_equal '<span title="a&quot;b">body</span>', content_tag(:span, "body", title: 'a"b')
  end

  test "tag proxy returns builder and renders attributes" do
    assert_kind_of ActionView::Helpers::TagHelper::TagBuilder, tag
    assert_equal 'type="text" disabled="disabled" aria-label="Search" data-user-id="7"',
      tag.attributes(type: :text, disabled: true, aria: { label: "Search" }, data: { user_id: 7 })
    assert_equal '<input type="text" />', tag(:input, type: :text, disabled: false)
    assert_equal '<input title="a&quot;b" />', tag(:input, { title: 'a"b' }, false, false)
    assert_equal '<input pattern="a&quot;b" />', tag(:input, { pattern: /a"b/ }, false, false)
    assert_equal '<br>', tag(:br, nil, true)
  end

  test "tag builder generated element helpers cover element types" do
    builder = tag

    assert_equal "<div></div>", builder.div
    assert_equal "<br>", builder.br
    assert_equal "<circle />", builder.circle
    assert_equal "<circle>dot</circle>", builder.circle("dot")
  end

  test "tag builder class definition helpers can define custom elements" do
    klass = Class.new(ActionView::Helpers::TagHelper::TagBuilder)
    ActiveSupport::CodeGenerator.batch(klass, __FILE__, __LINE__) do |code_generator|
      klass.define_element :customBox, code_generator: code_generator, method_name: :custom_box
      klass.define_void_element :voidThing, code_generator: code_generator, method_name: :void_thing
      klass.define_self_closing_element :selfThing, code_generator: code_generator, method_name: :self_thing
    end

    builder = klass.new(self)

    assert_equal "<customBox>content</customBox>", builder.custom_box("content")
    assert_equal "<voidThing>", builder.void_thing
    assert_equal "<selfThing />", builder.self_thing
    assert_equal "<selfThing>content</selfThing>", builder.self_thing("content")
  end

  test "define_element returns when method already exists" do
    ActionView::Helpers::TagHelper::TagBuilder.define_element(:div, code_generator: nil)

    assert_equal "<div></div>", tag.div
  end
end
