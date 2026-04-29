# frozen_string_literal: true

require "abstract_unit"
require "action_view/renderer/collection_renderer"

class CollectionRendererIteratorTest < ActiveSupport::TestCase
  def test_collection_iterator_delegates_collection_shape_and_preload_is_noop
    iterator = ActionView::CollectionRenderer::CollectionIterator.new([:a, :b])

    assert_equal [:a, :b], iterator.each.to_a
    assert_equal 2, iterator.size
    assert_equal 2, iterator.length
    assert_nil iterator.preload!
  end

  def test_collection_iterator_length_falls_back_to_size
    collection = Class.new do
      def each(&block) = [:a, :b].each(&block)
      def size = 2
    end.new
    iterator = ActionView::CollectionRenderer::CollectionIterator.new(collection)

    assert_equal 2, iterator.length
  end

  def test_same_collection_iterator_can_rebuild_for_another_collection
    iterator = ActionView::CollectionRenderer::SameCollectionIterator.new([:a], "items/item", [:item, :item_counter, :item_iteration])

    rebuilt = iterator.from_collection([:b, :c])

    assert_equal [[:b, ["items/item", :item, :item_counter, :item_iteration]], [:c, ["items/item", :item, :item_counter, :item_iteration]]], rebuilt.each_with_info.to_a
  end

  def test_preload_collection_iterator_preloads_and_rebuilds_with_relation
    relation = Class.new do
      attr_reader :preloaded_collection

      def initialize(loaded:)
        @loaded = loaded
      end

      def loaded? = @loaded
      def skip_preloading! = @skip_preloading = true
      def skip_preloading? = @skip_preloading
      def preload_associations(collection) = @preloaded_collection = collection
    end.new(loaded: false)

    iterator = ActionView::CollectionRenderer::PreloadCollectionIterator.new([:a, :b], "items/item", [:item, :item_counter, :item_iteration], relation)
    assert_predicate relation, :skip_preloading?

    assert_equal [[:a, ["items/item", :item, :item_counter, :item_iteration]], [:b, ["items/item", :item, :item_counter, :item_iteration]]], iterator.each_with_info.to_a
    assert_equal [:a, :b], relation.preloaded_collection

    rebuilt = iterator.from_collection([:c])
    assert_equal [[:c, ["items/item", :item, :item_counter, :item_iteration]]], rebuilt.each_with_info.to_a
  end

  def test_preload_collection_iterator_does_not_skip_preloading_when_relation_is_loaded
    relation = Class.new do
      def loaded? = true
      def skip_preloading! = @skip_preloading = true
      def skip_preloading? = @skip_preloading
      def preload_associations(_collection) = nil
    end.new

    ActionView::CollectionRenderer::PreloadCollectionIterator.new([:a], "items/item", [:item], relation)

    assert_not_predicate relation, :skip_preloading?
  end

  def test_mixed_collection_iterator_can_be_enumerated
    iterator = ActionView::CollectionRenderer::MixedCollectionIterator.new([:a, :b], [["a/path", :a], ["b/path", :b]])

    assert_equal [[:a, ["a/path", :a]], [:b, ["b/path", :b]]], iterator.each_with_info.to_a
  end
end
