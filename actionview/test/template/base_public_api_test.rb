# frozen_string_literal: true

require "abstract_unit"

class ActionView::BasePublicAPITest < ActiveSupport::TestCase
  class ArgumentErrorWithExternalBacktrace < ArgumentError
    Frame = Struct.new(:path, :lineno)

    def backtrace_locations
      [Frame.new("template.erb", 1), Frame.new("template.erb", 2)]
    end
  end

  def setup
    @old_caching = ActionView::Resolver.caching?
  end

  def teardown
    ActionView::Resolver.caching = @old_caching
  end

  test "ActionView eager_load loads helper and template namespaces" do
    helpers_loaded = false
    templates_loaded = false

    ActionView::Helpers.stub(:eager_load!, -> { helpers_loaded = true }) do
      ActionView::Template.stub(:eager_load!, -> { templates_loaded = true }) do
        ActionView.eager_load!
      end
    end

    assert helpers_loaded
    assert templates_loaded
  end

  test "cache template loading delegates to resolver caching" do
    ActionView::Base.cache_template_loading = true
    assert_predicate ActionView::Base, :cache_template_loading

    ActionView::Base.cache_template_loading = false
    assert_not ActionView::Base.cache_template_loading
  end

  test "constructors create views with paths context assigns and controller" do
    controller = BasicController.new
    path_set = ActionView::PathSet.new([])
    context = ActionView::LookupContext.new(path_set)

    empty_view = ActionView::Base.empty
    view_with_paths = ActionView::Base.with_view_paths(path_set, { title: "Hello" }, controller)
    view_with_context = ActionView::Base.with_context(context, { title: "Hello" }, controller)

    assert_instance_of ActionView::PathSet, empty_view.view_paths
    assert_equal [], empty_view.view_paths.paths
    assert_equal path_set, view_with_paths.view_paths
    assert_equal "Hello", view_with_paths.instance_variable_get(:@title)
    assert_same context, view_with_context.lookup_context
    assert_equal "Hello", view_with_context.instance_variable_get(:@title)
    assert_match(/ActionView::Base/, ActionView::Base.inspect)
  end

  test "compiled method container contract" do
    view_class = ActionView::Base.with_empty_template_cache
    view = view_class.with_context(ActionView::LookupContext.new([]))

    assert_same view_class, view.compiled_method_container
    assert_same view_class, view_class.compiled_method_container
    assert_match(/#<ActionView::Base:0x[0-9a-f]+>/, view.inspect)

    error = assert_raises(NotImplementedError) do
      ActionView::Base.with_context(ActionView::LookupContext.new([])).compiled_method_container
    end
    assert_includes error.message, "must implement `compiled_method_container`"
  end

  test "_run restores rendering state and handles strict locals" do
    view = ActionView::Base.with_empty_template_cache.with_context(ActionView::LookupContext.new([]))
    view.singleton_class.class_eval do
      def render_without_strict(_locals, buffer)
        buffer << "plain"
      end

      def render_with_strict(_locals, buffer, name:)
        buffer << name
      end

      def render_raises_argument(_locals, _buffer, **)
        raise ArgumentError, "raised inside template"
      end

      def render_raises_external_argument(_locals, _buffer, **)
        raise ArgumentErrorWithExternalBacktrace, "external argument error"
      end
    end

    old_buffer = view.output_buffer
    buffer = ActionView::OutputBuffer.new

    view._run(:render_without_strict, Object.new, {}, buffer, add_to_stack: false)
    assert_equal "plain", buffer.to_s
    assert_same old_buffer, view.output_buffer

    strict_buffer = ActionView::OutputBuffer.new
    view._run(:render_with_strict, Object.new, { name: "strict" }, strict_buffer, has_strict_locals: true)
    assert_equal "strict", strict_buffer.to_s
    template = Struct.new(:short_identifier).new("inline template")
    assert_raises(ActionView::StrictLocalsError) do
      view._run(:render_with_strict, template, {}, ActionView::OutputBuffer.new, has_strict_locals: true)
    end
    error = assert_raises(ActionView::StrictLocalsError) do
      view._run(:render_raises_argument, template, {}, ActionView::OutputBuffer.new, has_strict_locals: true)
    end
    assert_includes error.message, "raised inside template"
    error = assert_raises(ArgumentErrorWithExternalBacktrace) do
      view._run(:render_raises_external_argument, template, {}, ActionView::OutputBuffer.new, has_strict_locals: true)
    end
    assert_equal "external argument error", error.message
  end

  test "in rendering context prepends html fallback for javascript formats" do
    view = ActionView::Base.with_empty_template_cache.with_context(ActionView::LookupContext.new([]))
    original_renderer = view.view_renderer
    original_context = view.lookup_context

    yielded_renderer = nil
    view.in_rendering_context(formats: [:js]) do |renderer|
      yielded_renderer = renderer
      assert_equal [:js, :html], view.lookup_context.formats
      assert_not_same original_renderer, renderer
    end

    assert yielded_renderer
    assert_same original_renderer, view.view_renderer
    assert_same original_context, view.lookup_context

    view.in_rendering_context(formats: [:html]) do |renderer|
      assert_equal [:html], view.lookup_context.formats
      assert_not_same original_renderer, renderer
    end

    view.in_rendering_context({}) do |renderer|
      assert_same original_renderer, renderer
    end
  end
end
