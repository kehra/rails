# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"

class ViewPathsPublicApiTest < ActiveSupport::TestCase
  class AbstractBase
    include ActionView::ViewPaths

    def self.abstract? = true
    def self.controller_path = "abstract_base"
  end

  class Controller < AbstractBase
    def self.abstract? = false
    def self.controller_path = "controller"
  end

  class ParentBase
    include ActionView::ViewPaths

    def self.abstract? = true
    def self.controller_path = "parent_base"
  end

  class ParentController < ParentBase
    def self.abstract? = false
    def self.controller_path = "parent"
  end

  class ChildController < ParentController
    def self.abstract? = false
    def self.controller_path = "child"
  end

  setup do
    @controller_old_paths = Controller._view_paths
    @parent_old_paths = ParentController._view_paths
    @child_old_paths = ChildController._view_paths
  end

  teardown do
    Controller._view_paths = @controller_old_paths
    ParentController._view_paths = @parent_old_paths
    ChildController._view_paths = @child_old_paths
  end

  test "class view paths accessors build path sets" do
    Dir.mktmpdir do |dir|
      Controller.view_paths = dir

      assert_instance_of ActionView::PathSet, Controller._view_paths
      assert_equal Controller._view_paths, Controller.view_paths
      assert_equal File.expand_path(dir), Controller.view_paths.first.to_s
    end
  end

  test "class append and prepend view paths preserve order" do
    Dir.mktmpdir do |first|
      Dir.mktmpdir do |second|
        Controller.view_paths = []

        Controller.append_view_path(first)
        Controller.prepend_view_path(second)

        assert_equal [File.expand_path(second), File.expand_path(first)], Controller.view_paths.map(&:to_s)
      end
    end
  end

  test "class view paths accepts existing path set without rebuilding" do
    path_set = ActionView::PathSet.new([])

    Controller.view_paths = path_set

    assert_same path_set, Controller._view_paths
  end

  test "prefixes use local prefixes for abstract superclasses and append parent prefixes otherwise" do
    assert_equal ["controller"], Controller._prefixes
    assert_equal ["child", "parent"], ChildController._prefixes
  end

  test "instance lookup context uses class view paths details and prefixes" do
    Dir.mktmpdir do |dir|
      Controller.view_paths = dir
      controller = Controller.new

      assert_equal({}, controller.details_for_lookup)
      assert_equal ["controller"], controller.lookup_context.prefixes
      assert_equal File.expand_path(dir), controller.lookup_context.view_paths.first.to_s
      assert_same controller.lookup_context, controller.lookup_context
    end
  end

  test "instance append and prepend view paths update lookup context" do
    Dir.mktmpdir do |base|
      Dir.mktmpdir do |append|
        Dir.mktmpdir do |prepend|
          Controller.view_paths = base
          controller = Controller.new

          controller.append_view_path(append)
          controller.prepend_view_path(prepend)

          assert_equal [File.expand_path(prepend), File.expand_path(base), File.expand_path(append)], controller.lookup_context.view_paths.map(&:to_s)
        end
      end
    end
  end
end
