# frozen_string_literal: true

require "abstract_unit"
require "action_view/path_registry"
require "tmpdir"

class ActionViewPathRegistryTest < ActiveSupport::TestCase
  class ParentView; end
  class ChildView < ParentView; end

  setup do
    @hook_calls = 0
    @hook = -> { @hook_calls += 1 }
    ActionView::PathRegistry.file_system_resolver_hooks << @hook
  end

  teardown do
    ActionView::PathRegistry.file_system_resolver_hooks.delete(@hook)
  end

  test "view paths are looked up through superclass fallback" do
    paths = ActionView::PathSet.new([])
    ActionView::PathRegistry.set_view_paths(ParentView, paths)

    assert_same paths, ActionView::PathRegistry.get_view_paths(ChildView)
  end

  test "casts filesystem resolver paths and preserves resolver instances" do
    Dir.mktmpdir("path-registry") do |dir|
      resolver = ActionView::FileSystemResolver.new(dir)

      cast = ActionView::PathRegistry.cast_file_system_resolvers([dir, resolver])

      assert_kind_of ActionView::FileSystemResolver, cast.first
      assert_same resolver, cast.second
      assert_equal 1, @hook_calls
      assert_includes ActionView::PathRegistry.all_file_system_resolvers, cast.first
      assert_includes ActionView::PathRegistry.all_resolvers, resolver
    end
  end

  test "reuses cached filesystem resolver without running hooks" do
    Dir.mktmpdir("path-registry-cached") do |dir|
      first = ActionView::PathRegistry.cast_file_system_resolvers(dir).first
      hook_calls = @hook_calls
      second = ActionView::PathRegistry.cast_file_system_resolvers(dir).first

      assert_same first, second
      assert_equal hook_calls, @hook_calls
    end
  end
end
