# frozen_string_literal: true

require "abstract_unit"
require "rails/application/routes_reloader"

class RoutesReloaderPublicContractTest < ActiveSupport::TestCase
  test "initializes empty reload state and builds updater with paths and external routes" do
    reloader = Rails::Application::RoutesReloader.new(file_watcher: Watcher)
    reloader.paths << "config/routes.rb"
    reloader.external_routes << Pathname.new("engines/blog/config/routes.rb")

    updater = reloader.send(:updater)

    assert_equal [ "config/routes.rb" ], reloader.paths
    assert_equal [], reloader.route_sets
    assert_not reloader.eager_load
    assert_equal [ "config/routes.rb" ], updater.paths
    assert_equal({ "engines/blog/config/routes.rb" => %w(rb) }, updater.dirs)
  end

  test "execute delegates to updater" do
    reloader = Rails::Application::RoutesReloader.new(file_watcher: Watcher)

    reloader.execute

    assert reloader.send(:updater).executed
  end

  test "execute unless loaded runs once and reports whether it loaded routes" do
    reloader = Rails::Application::RoutesReloader.new(file_watcher: Watcher)

    assert reloader.execute_unless_loaded
    assert reloader.send(:updater).executed
    assert_not reloader.execute_unless_loaded
  end

  test "reload clears loads finalizes eager loads and always reverts route sets" do
    route_set = RouteSet.new
    reloader = Rails::Application::RoutesReloader.new(file_watcher: Watcher)
    reloader.route_sets << route_set
    reloader.paths << route_file = Tempfile.new([ "routes", ".rb" ]).path
    reloader.eager_load = true
    after_load_called = false
    reloader.run_once_after_load_paths = -> { after_load_called = true }

    File.write(route_file, "$routes_reloader_public_contract_loaded = true")

    reloader.reload!

    assert $routes_reloader_public_contract_loaded
    assert after_load_called
    assert route_set.cleared
    assert route_set.finalized
    assert route_set.eager_loaded
    assert_not route_set.disable_clear_and_finalize
  ensure
    $routes_reloader_public_contract_loaded = false
    FileUtils.rm_f(route_file) if route_file
  end

  test "reload reverts route sets when loading raises" do
    route_set = RouteSet.new
    reloader = Rails::Application::RoutesReloader.new(file_watcher: Watcher)
    reloader.route_sets << route_set
    reloader.paths << missing_route = "/tmp/missing-routes-reloader-contract-#{$$}.rb"

    assert_raises(LoadError) { reloader.reload! }
    assert_not route_set.disable_clear_and_finalize
  ensure
    FileUtils.rm_f(missing_route) if missing_route
  end

  class Watcher
    attr_reader :paths, :dirs
    attr_accessor :executed

    def initialize(paths, dirs, &block)
      @paths = paths
      @dirs = dirs
      @block = block
    end

    def execute
      @executed = true
      @block.call
    end
  end

  class RouteSet
    attr_accessor :disable_clear_and_finalize
    attr_reader :cleared, :finalized, :eager_loaded

    def clear!
      @cleared = true
    end

    def finalize!
      @finalized = true
    end

    def eager_load!
      @eager_loaded = true
    end
  end
end
