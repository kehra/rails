# frozen_string_literal: true

require "abstract_unit"

class TemplateHandlersPublicApiTest < ActiveSupport::TestCase
  Handler = ->(_template, source) { source }

  test "template handler extensions are sorted strings" do
    ActionView::Template.register_template_handler :z_public_api, :a_public_api, Handler

    extensions = ActionView::Template.template_handler_extensions

    assert_includes extensions, "a_public_api"
    assert_includes extensions, "z_public_api"
    assert_operator extensions.index("a_public_api"), :<, extensions.index("z_public_api")
  ensure
    ActionView::Template.unregister_template_handler :z_public_api, :a_public_api
  end

  test "unregistering current default handler clears default handler fallback" do
    original_default = ActionView::Template.handler_for_extension(:unknown_public_api_extension)
    default_handler = ->(_template, source) { source }
    ActionView::Template.register_default_template_handler :public_api_default, default_handler

    assert_same default_handler, ActionView::Template.handler_for_extension(:unknown_public_api_extension)

    ActionView::Template.unregister_template_handler :public_api_default

    assert_nil ActionView::Template.registered_template_handler(:public_api_default)
    assert_nil ActionView::Template.handler_for_extension(:unknown_public_api_extension)
  ensure
    ActionView::Template.register_default_template_handler :raw, original_default if original_default
    ActionView::Template.unregister_template_handler :public_api_default
  end

  test "raw html and builder handlers return compilable source" do
    raw_source = ActionView::Template::Handlers::Raw.new.call(nil, "<p>raw</p>")
    html_source = ActionView::Template::Handlers::Html.new.call(nil, "<p>html</p>")
    builder_source = ActionView::Template::Handlers::Builder.new.call(nil, "xml.span('builder')")

    assert_equal "\"<p>raw</p>\".html_safe;", raw_source
    assert_equal "ActionView::OutputBuffer.new \"<p>html</p>\".html_safe;", html_source
    assert_includes builder_source, "::Builder::XmlMarkup.new"
    assert_includes builder_source, "xml.span('builder')"
  end

  test "erb handler class call and streaming support" do
    template = ActionView::Template.new("Hello", "hello.html.erb", ActionView::Template.handler_for_extension(:erb), locals: [], format: :html)

    assert ActionView::Template::Handlers::ERB.new.supports_streaming?
    assert_includes ActionView::Template::Handlers::ERB.call(template, "Hello"), "Hello"
  end

  test "erb handler strips trailing newlines when configured" do
    old_strip = ActionView::Template::Handlers::ERB.strip_trailing_newlines
    ActionView::Template::Handlers::ERB.strip_trailing_newlines = true
    template = ActionView::Template.new("Hello\n", "hello.html.erb", ActionView::Template.handler_for_extension(:erb), locals: [], format: :html)

    assert_not_includes ActionView::Template::Handlers::ERB.new.call(template, "Hello\n"), "Hello\\n"
  ensure
    ActionView::Template::Handlers::ERB.strip_trailing_newlines = old_strip
  end

  test "erb handler annotates html templates when configured" do
    old_annotate = ActionView::Base.annotate_rendered_view_with_filenames
    ActionView::Base.annotate_rendered_view_with_filenames = true
    template = ActionView::Template.new("Hello", "hello.html.erb", ActionView::Template.handler_for_extension(:erb), locals: [], format: :html)

    source = ActionView::Template::Handlers::ERB.new.call(template, "Hello")

    assert_includes source, "<!-- BEGIN hello.html.erb"
    assert_includes source, "<!-- END hello.html.erb -->"
  ensure
    ActionView::Base.annotate_rendered_view_with_filenames = old_annotate
  end

  test "erb translate location returns nil for missing highlight" do
    spot = { script_lines: [], first_lineno: 1, last_lineno: 1, first_column: 1, last_column: 1, snippet: "" }

    assert_nil ActionView::Template::Handlers::ERB.new.translate_location(spot, nil, "<%= missing %>")
  end

  test "erb private line offset handles compiled templates shorter than source" do
    handler = ActionView::Template::Handlers::ERB.new

    assert_equal 0, handler.send(:find_lineno_offset, ["highlight", "compiled", "template"], ["highlight"], "highlight", 1)
  end
end
