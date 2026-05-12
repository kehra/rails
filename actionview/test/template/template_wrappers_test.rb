# frozen_string_literal: true

require "abstract_unit"
require "action_view/template/types"
require "tempfile"

class TemplateWrapperPublicApiTest < ActiveSupport::TestCase
  class Renderable
    attr_reader :context

    attr_reader :locals

    def render_in(context, locals: {})
      @context = context
      @locals = locals
      "rendered #{locals.fetch(:name, "world")}"
    end

    def format
      :html
    end
  end

  class MissingRenderIn
    def method(name)
      raise NameError, "missing implementation" if name == :render_in
      super
    end

    def respond_to?(name, include_private = false)
      return false if name == :render_in
      super
    end
  end

  class BrokenRenderable
    def render_in(_context, **)
      raise NoMethodError, "internal failure"
    end
  end

  test "html template escapes source and exposes html template identity" do
    template = ActionView::Template::HTML.new("<strong>safe?</strong>", :html)

    assert_equal :html, template.format
    assert_equal "html template", template.identifier
    assert_equal "html template", template.inspect
    assert_equal "&lt;strong&gt;safe?&lt;/strong&gt;", template.to_str
    assert_equal "&lt;strong&gt;safe?&lt;/strong&gt;", template.render
  end

  test "raw file template reads file and reports non streaming support" do
    file = Tempfile.new(["action_view_template", ".html"])
    file.write("raw file body")
    file.close

    template = ActionView::Template::RawFile.new(file.path)

    assert_equal file.path, template.identifier
    assert_equal :html, template.format
    assert_equal Mime[:html], template.type
    assert_equal "raw file body", template.render
    assert_not template.supports_streaming?
  ensure
    file&.close!
  end

  test "renderable template delegates to render_in and exposes optional format" do
    context = Object.new
    renderable = Renderable.new
    template = ActionView::Template::Renderable.new(renderable)

    assert_equal "TemplateWrapperPublicApiTest::Renderable", template.identifier
    assert_equal :html, template.format
    assert_equal "rendered local", template.render(context, { name: "local" })
    assert_same context, renderable.context
    assert_equal({ name: "local" }, renderable.locals)
  end

  test "renderable template reports missing render_in as argument error" do
    error = assert_raises(ArgumentError) do
      ActionView::Template::Renderable.new(MissingRenderIn.new).render(Object.new, {})
    end

    assert_match "is not a renderable object", error.message
  end

  test "renderable template reraises internal render_in no method errors" do
    assert_raises(NoMethodError) do
      ActionView::Template::Renderable.new(BrokenRenderable.new).render(Object.new, {})
    end
  end

  test "text template returns the original string as text" do
    template = ActionView::Template::Text.new("plain text")

    assert_equal :text, template.format
    assert_equal "text template", template.identifier
    assert_equal "text template", template.inspect
    assert_equal "plain text", template.to_str
    assert_equal "plain text", template.render
  end

  test "template source file reads binary contents" do
    file = Tempfile.new("action_view_source")
    file.binmode
    file.write("source bytes")
    file.close

    source = ActionView::Template::Sources::File.new(file.path)

    assert_equal "source bytes", source.to_s
  ensure
    file&.close!
  end

  test "simple type supports lookup coercion string conversion and equality" do
    html = ActionView::Template::SimpleType[:html]

    assert_same html, ActionView::Template::SimpleType[html]
    assert_equal :html, html.ref
    assert_equal :html, html.to_sym
    assert_equal "html", html.to_s
    assert_equal "html", html.to_str
    assert_equal html, :html
    assert_not_equal html, :json
    assert_not_equal html, nil
    assert ActionView::Template::SimpleType.valid_symbols?([:html, :text])
    assert_not ActionView::Template::SimpleType.valid_symbols?([:html, :unknown])
  end
end
