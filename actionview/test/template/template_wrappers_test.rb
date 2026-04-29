# frozen_string_literal: true

require "abstract_unit"
require "tempfile"

class TemplateWrapperPublicApiTest < ActiveSupport::TestCase
  class Renderable
    attr_reader :context

    def render_in(context)
      @context = context
      "rendered"
    end

    def format
      :html
    end
  end

  class MissingRenderIn
    def render_in(_context)
      raise NoMethodError, "missing implementation"
    end

    def respond_to?(name, include_private = false)
      return false if name == :render_in
      super
    end
  end

  class BrokenRenderable
    def render_in(_context)
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
    assert_equal "rendered", template.render(context)
    assert_same context, renderable.context
  end

  test "renderable template reports missing render_in as argument error" do
    error = assert_raises(ArgumentError) do
      ActionView::Template::Renderable.new(MissingRenderIn.new).render(Object.new)
    end

    assert_match "is not a renderable object", error.message
  end

  test "renderable template reraises internal render_in no method errors" do
    assert_raises(NoMethodError) do
      ActionView::Template::Renderable.new(BrokenRenderable.new).render(Object.new)
    end
  end
end
