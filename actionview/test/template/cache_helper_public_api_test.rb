# frozen_string_literal: true

require "abstract_unit"

class CacheHelperPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::CacheHelper

  class CacheController
    attr_accessor :perform_caching, :store, :writes

    def initialize
      @perform_caching = true
      @store = {}
      @writes = []
    end

    def read_fragment(name, options)
      store[[name, options]]
    end

    def write_fragment(name, fragment, options)
      writes << [name, fragment, options]
      store[[name, options]] = fragment
    end

    def url_for(options)
      "http://example.com/#{options.fetch(:id)}"
    end

    def lookup_context
      :lookup_context
    end
  end

  attr_reader :controller

  def setup
    super
    @controller = CacheController.new
    @view_renderer = Struct.new(:cache_hits).new({})
  end

  def view_cache_dependencies
    []
  end

  def test_cache_writes_misses_and_reads_hits_when_caching_enabled
    cache("greeting", skip_digest: true) { concat "Hello" }
    assert_equal "Hello", output_buffer.to_s
    assert_equal [["greeting", "Hello", { skip_digest: true }]], controller.writes
    assert_equal({ nil => :miss }, @view_renderer.cache_hits)

    self.output_buffer = ActionView::OutputBuffer.new
    cache("greeting", skip_digest: true) { concat "Unused" }
    assert_equal "Hello", output_buffer.to_s
    assert_equal({ nil => :hit }, @view_renderer.cache_hits)
  end

  def test_cache_yields_directly_when_caching_disabled
    controller.perform_caching = false

    assert_nil cache("name") { concat "Direct" }
    assert_equal "Direct", output_buffer.to_s
    assert_empty controller.writes
  end

  def test_cache_if_cache_unless_and_uncacheable_track_registry_state
    assert_not caching?
    assert_nil uncacheable!

    assert_nil cache_if(false, "name") { concat "if-false" }
    assert_equal "if-false", output_buffer.to_s

    self.output_buffer = ActionView::OutputBuffer.new
    assert_nil cache_if(true, "if-true", skip_digest: true) { concat "if-true" }
    assert_equal "if-true", output_buffer.to_s

    self.output_buffer = ActionView::OutputBuffer.new
    assert_nil cache_unless(true, "name") { concat "unless-true" }
    assert_equal "unless-true", output_buffer.to_s

    assert_raises(ActionView::Helpers::CacheHelper::UncacheableFragmentError) do
      cache("tracked", skip_digest: true) { uncacheable! }
    end
    assert_not caching?

    ActionView::Helpers::CacheHelper::CachingRegistry.track_caching do
      assert ActionView::Helpers::CacheHelper::CachingRegistry.caching?
    end
    assert_not ActionView::Helpers::CacheHelper::CachingRegistry.caching?
  end

  def test_cache_tracks_current_template_cache_hits
    @current_template = Struct.new(:virtual_path).new("templates/show")

    cache("with-template", skip_digest: true) { concat "Template miss" }
    assert_equal({ "templates/show" => :miss }, @view_renderer.cache_hits)

    @view_renderer.cache_hits.clear
    self.output_buffer = ActionView::OutputBuffer.new
    cache("with-template", skip_digest: true) { concat "Unused" }
    assert_equal "Template miss", output_buffer.to_s
    assert_equal({ "templates/show" => :hit }, @view_renderer.cache_hits)
  end

  def test_cache_fragment_name_handles_skip_digest_hashes_and_digest_paths
    assert_equal "plain", cache_fragment_name("plain", skip_digest: true)
    assert_equal "example.com/7", cache_fragment_name({ id: 7 }, skip_digest: false)
    assert_equal ["templates/show:digest", "plain"], cache_fragment_name("plain", digest_path: "templates/show:digest")

    @current_template = Struct.new(:virtual_path, :format).new("posts/show", :html)
    ActionView::Digestor.stub(:digest, "abc123") do
      assert_equal ["posts/show:abc123", "plain"], cache_fragment_name("plain")
    end
  end

  def test_fragment_for_works_without_view_renderer_tracking
    helper_class = Class.new do
      include ActionView::Helpers::CacheHelper

      attr_accessor :controller, :output_buffer

      def concat(string)
        output_buffer.safe_concat(string)
      end
    end
    helper = helper_class.new
    helper.controller = controller
    helper.output_buffer = ActionView::OutputBuffer.new

    assert_equal "direct miss", helper.send(:fragment_for, "direct", skip_digest: true) { helper.concat "direct miss" }
    assert_equal "direct miss", helper.send(:fragment_for, "direct", skip_digest: true) { helper.concat "unused" }
  end

  def test_digest_path_from_template_uses_digest_when_present
    template = Struct.new(:virtual_path, :format).new("posts/show", :html)

    ActionView::Digestor.stub(:digest, "abc123") do
      assert_equal "posts/show:abc123", send(:digest_path_from_template, template)
    end

    ActionView::Digestor.stub(:digest, nil) do
      assert_equal "posts/show", send(:digest_path_from_template, template)
    end
  end
end
