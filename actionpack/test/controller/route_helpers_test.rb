# frozen_string_literal: true

require "abstract_unit"

class RouteHelperIntegrationTest < ActionDispatch::IntegrationTest
  class FooController < ApplicationController
  end

  class RoutesHelperRoutes
    attr_reader :include_path_helpers

    def url_helpers(include_path_helpers)
      @include_path_helpers = include_path_helpers
      Module.new do
        def fallback_route_helper; :fallback; end
      end
    end
  end

  module RouteHelperNamespace
    def self.railtie_routes_url_helpers(include_path_helpers)
      @include_path_helpers = include_path_helpers
      Module.new do
        def namespaced_route_helper; :namespaced; end
      end
    end

    def self.include_path_helpers
      @include_path_helpers
    end
  end

  # We define many routes in these modules after they have been included into
  # the controllers. For boot performance, it's important that we don't
  # duplicate these modules and make method cache invalidation expensive.
  # https://github.com/rails/rails/pull/37927
  test "routes helpers include fallback route helpers when no namespace provides railtie helpers" do
    routes = RoutesHelperRoutes.new
    parent = Class.new
    parent.extend AbstractController::Railties::RoutesHelpers.with(routes, false)
    child = Class.new(parent)

    assert_equal false, routes.include_path_helpers
    assert_equal :fallback, child.new.fallback_route_helper
  end

  test "routes helpers prefer namespace railtie route helpers" do
    routes = RoutesHelperRoutes.new
    RouteHelperNamespace.const_set(:ParentController, Class.new)
    RouteHelperNamespace::ParentController.extend AbstractController::Railties::RoutesHelpers.with(routes, true)
    RouteHelperNamespace.module_eval("class ChildController < ParentController; end", __FILE__, __LINE__)

    assert_nil routes.include_path_helpers
    assert_equal true, RouteHelperNamespace.include_path_helpers
    assert_equal :namespaced, RouteHelperNamespace::ChildController.new.namespaced_route_helper
  ensure
    RouteHelperNamespace.send(:remove_const, :ParentController) if RouteHelperNamespace.const_defined?(:ParentController, false)
    RouteHelperNamespace.send(:remove_const, :ChildController) if RouteHelperNamespace.const_defined?(:ChildController, false)
  end

  test "only includes one module with route helpers" do
    url_helpers_module = SharedTestRoutes.named_routes.url_helpers_module
    path_helpers_module = SharedTestRoutes.named_routes.path_helpers_module

    assert_operator FooController, :<, url_helpers_module
    assert_operator ApplicationController, :<, url_helpers_module
    assert_not_operator ActionController::Base, :<, url_helpers_module

    assert_operator FooController, :<, path_helpers_module
    assert_operator ApplicationController, :<, path_helpers_module
    assert_not_operator ActionController::Base, :<, path_helpers_module

    included_modules = FooController.ancestors.grep_v(Class)
    included_modules -= [url_helpers_module, path_helpers_module]

    modules_with_routes = included_modules.select do |mod|
      mod < url_helpers_module || mod < path_helpers_module
    end

    assert_equal 1, modules_with_routes.size
  end
end
