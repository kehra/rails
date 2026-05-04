# frozen_string_literal: true

require "abstract_unit"
require "action_view/cache_expiry"
require "action_view/path_registry"
require "tmpdir"

class ActionViewCacheExpiryTest < ActiveSupport::TestCase
  class Watcher
    class << self
      attr_accessor :instances, :updated
    end

    self.instances = []
    self.updated = false

    attr_reader :files, :dirs
    attr_writer :updated

    def initialize(files, dirs, &block)
      @files = files
      @dirs = dirs
      @block = block
      @updated = self.class.updated
      @executed = false
      self.class.instances << self
    end

    def updated?
      @updated
    end

    def execute
      @executed = true
      @block.call
    end

    def executed?
      @executed
    end
  end

  setup do
    Watcher.instances = []
    Watcher.updated = false
    @reloader = ActionView::CacheExpiry::ViewReloader.new(watcher: Watcher)
  end

  teardown do
    ActionView::PathRegistry.file_system_resolver_hooks.delete_if do |hook|
      hook.respond_to?(:receiver) && hook.receiver.equal?(@reloader)
    end
  end

  test "updated builds a watcher from registered filesystem resolver paths" do
    Dir.mktmpdir("view-reloader") do |dir|
      ActionView::PathRegistry.cast_file_system_resolvers(dir)

      assert_not @reloader.updated?
      assert_includes Watcher.instances.last.dirs, File.expand_path(dir)
      assert_equal [], Watcher.instances.last.files
    end
  end

  test "updated preserves previous changes when rebuilding the watcher" do
    Dir.mktmpdir("view-reloader-old") do |old_dir|
      ActionView::PathRegistry.cast_file_system_resolvers(old_dir)
      assert_not @reloader.updated?

      Watcher.instances.last.updated = true
      Dir.mktmpdir("view-reloader-new") do |new_dir|
        ActionView::PathRegistry.cast_file_system_resolvers(new_dir)
        Watcher.updated = false
        @reloader.rebuild_watcher

        assert @reloader.updated?
        assert_equal 2, Watcher.instances.length
      end
    end
  end

  test "execute is a no-op until the watcher is built and then runs the watcher" do
    @reloader.execute
    assert_empty Watcher.instances

    Dir.mktmpdir("view-reloader-execute") do |dir|
      ActionView::PathRegistry.cast_file_system_resolvers(dir)
      @reloader.updated?

      watcher = Watcher.instances.last
      @reloader.execute
      assert_predicate watcher, :executed?
    end
  end

  test "updated reuses the watcher when the resolver directories are unchanged" do
    Dir.mktmpdir("view-reloader-stable") do |dir|
      ActionView::PathRegistry.cast_file_system_resolvers(dir)

      assert_not @reloader.updated?
      @reloader.__send__(:rebuild_watcher)
      assert_not @reloader.updated?
      assert_equal 1, Watcher.instances.length
    end
  end
end
