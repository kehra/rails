# frozen_string_literal: true

require "abstract_unit"
require "action_view/renderer/partial_renderer/collection_caching"

class CollectionCachingPublicContractTest < ActiveSupport::TestCase
  Rendered = Struct.new(:body, :template)
  Template = Struct.new(:virtual_path)

  class Probe
    include ActionView::CollectionCaching

    def initialize(options = {})
      @options = options
    end

    def callable_cache_key_for_test = send(:callable_cache_key)
    def callable_cache_key_present_for_test = send(:callable_cache_key?)
    def expanded_cache_key_for_test(key, view, template, digest_path) = send(:expanded_cache_key, key, view, template, digest_path)
    def collection_by_cache_keys_for_test(view, template, collection) = send(:collection_by_cache_keys, view, template, collection)
    def fetch_or_cache_partial_for_test(cached_partials, template, order_by:, &block) = send(:fetch_or_cache_partial, cached_partials, template, order_by:, &block)

    private
      def build_rendered_template(content, template)
        Rendered.new(content, template)
      end
  end

  class View
    def digest_path_from_template(template) = template.virtual_path
    def cache_fragment_name(key, digest_path:) = key
    def combined_fragment_cache_key(key) = key
  end

  class Collection < Array
    attr_reader :preloaded

    def preload!
      @preloaded = true
    end
  end

  setup do
    Probe.collection_cache = ActiveSupport::Cache::MemoryStore.new
  end

  test "callable cache key can come from cached hash key or cached callable" do
    callable = ->(item) { "key/#{item}" }

    assert_same callable, Probe.new(cached: { key: callable }).callable_cache_key_for_test
    assert_same callable, Probe.new(cached: callable).callable_cache_key_for_test
    assert_nil Probe.new(cached: true).callable_cache_key_for_test
    assert_predicate Probe.new(cached: callable), :callable_cache_key_present_for_test
  end

  test "collection by cache keys preloads for callable cache key and preserves order" do
    callable = ->(item) { "key/#{item}" }
    probe = Probe.new(cached: callable)
    collection = Collection.new([:a, :b])
    template = Template.new("items/_item")

    keyed, ordered = probe.collection_by_cache_keys_for_test(View.new, template, collection)

    assert_predicate collection, :preloaded
    assert_equal ["key/a", "key/b"], ordered
    assert_equal({ "key/a" => :a, "key/b" => :b }, keyed)
  end

  test "expanded cache key duplicates frozen keys for mutable cache stores" do
    key = "frozen-key".freeze

    expanded = Probe.new(cached: true).expanded_cache_key_for_test(key, View.new, Template.new("items/_item"), "items/_item")

    assert_equal "frozen-key", expanded
    assert_not_same key, expanded
    assert_not_predicate expanded, :frozen?
  end

  test "fetch or cache partial writes plain body and preserves cached entries" do
    probe = Probe.new(cached: true)
    cached = { "cached" => "Cached body" }
    yielded = false

    keyed = probe.fetch_or_cache_partial_for_test(cached, Template.new("items/_item"), order_by: ["cached", "missing"]) do
      yielded = true
      Rendered.new("Fresh body", Template.new("items/_item"))
    end

    assert yielded
    assert_equal "Cached body", keyed["cached"].body
    assert_equal "Fresh body", keyed["missing"].body
    assert_equal "Fresh body", Probe.collection_cache.read("missing")
  end
end
