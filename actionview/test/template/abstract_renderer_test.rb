# frozen_string_literal: true

require "abstract_unit"
require "action_view/renderer/abstract_renderer"

class AbstractRendererPublicApiTest < ActiveSupport::TestCase
  TemplateStub = Struct.new(:format)
  ObjectWithPartialPath = Struct.new(:partial_path) do
    def to_partial_path = partial_path
  end
  ObjectWithModel = Struct.new(:model) do
    def to_model = model
  end
  ViewStub = Struct.new(:prefix_partial_path_with_controller_namespace)

  class ObjectRenderingBase < ActionView::AbstractRenderer
    def initialize(lookup_context, _options)
      super(lookup_context)
    end
  end

  class ObjectRenderingRenderer < ObjectRenderingBase
    include ActionView::AbstractRenderer::ObjectRendering

    def initialize(lookup_context, options = {})
      @options = options
      super
    end

    def local_variable_for(path)
      send(:local_variable, path)
    end

    def partial_path_for(object, view)
      send(:partial_path, object, view)
    end

    def merge_prefix(prefix, object_path)
      send(:merge_prefix_into_object_path, prefix, object_path)
    end
  end

  def lookup_context(prefixes = ["admin/posts"])
    ActionView::LookupContext.new([], {}, prefixes)
  end

  test "abstract renderer stores lookup context and render is abstract" do
    context = lookup_context
    renderer = ActionView::AbstractRenderer.new(context)

    assert_same context, renderer.instance_variable_get(:@lookup_context)
    assert_raises(NotImplementedError) { renderer.render }
  end

  test "rendered template exposes body template and format" do
    template = TemplateStub.new(:html)
    rendered = ActionView::AbstractRenderer::RenderedTemplate.new("body", template)

    assert_equal "body", rendered.body
    assert_same template, rendered.template
    assert_equal :html, rendered.format
  end

  test "rendered collection joins bodies with spacer and exposes first format" do
    first = ActionView::AbstractRenderer::RenderedTemplate.new("one", TemplateStub.new(:html))
    second = ActionView::AbstractRenderer::RenderedTemplate.new("two", TemplateStub.new(:html))
    spacer = ActionView::AbstractRenderer::RenderedTemplate::EMPTY_SPACER.dup
    spacer.body = " | "
    collection = ActionView::AbstractRenderer::RenderedCollection.new([first, second], spacer)

    assert_equal "one | two", collection.body
    assert_predicate collection.body, :html_safe?
    assert_equal :html, collection.format
  end

  test "empty rendered collection keeps format and has nil body" do
    collection = ActionView::AbstractRenderer::RenderedCollection.empty(:json)

    assert_equal :json, collection.format
    assert_nil collection.body
  end

  test "object rendering derives local variables and validates names" do
    renderer = ObjectRenderingRenderer.new(lookup_context, {})

    assert_equal :post, renderer.local_variable_for("posts/_post.html.erb")
    assert_equal :"", renderer.local_variable_for("posts/")

    invalid = assert_raises(ArgumentError) { renderer.local_variable_for("posts/\n.html.erb") }
    assert_match "not a valid Ruby identifier", invalid.message

    as_renderer = ObjectRenderingRenderer.new(lookup_context, as: :entry)
    assert_equal :entry, as_renderer.local_variable_for("posts/_post.html.erb")

    invalid_as = ObjectRenderingRenderer.new(lookup_context, as: "Entry")
    error = assert_raises(ArgumentError) { invalid_as.local_variable_for("posts/_post.html.erb") }
    assert_match "option `as` is not a valid Ruby identifier", error.message
  end

  test "object rendering resolves partial paths through model and optional namespace prefix" do
    renderer = ObjectRenderingRenderer.new(lookup_context(["admin/posts"]), {})
    post = ObjectWithPartialPath.new("posts/post")
    wrapper = ObjectWithModel.new(post)

    assert_equal "admin/posts/post", renderer.partial_path_for(wrapper, ViewStub.new(true))
    assert_equal "posts/post", renderer.partial_path_for(post, ViewStub.new(false))

    error = assert_raises(ArgumentError) { renderer.partial_path_for(Object.new, ViewStub.new(false)) }
    assert_match "ActiveModel-compatible object", error.message
  end

  test "object rendering namespace merge preserves shared prefixes" do
    renderer = ObjectRenderingRenderer.new(lookup_context, {})

    assert_equal "admin/posts/post", renderer.merge_prefix("admin/posts", "posts/post")
    assert_equal "admin/comments/comment", renderer.merge_prefix("admin/posts", "comments/comment")
    assert_equal "admin/comments/comment", renderer.merge_prefix("admin/posts", "admin/comments/comment")
    assert_equal "posts/post", renderer.merge_prefix("admin", "posts/post")
  end
end
