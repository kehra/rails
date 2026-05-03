# frozen_string_literal: true

require "abstract_unit"
require "rack/mock"
require "rails/engine/lazy_route_set"

module Rails
  class Engine
    class LazyRouteSetPublicContractTest < ActiveSupport::TestCase
      FakeApplication = Struct.new(:reloads, :reload_result) do
        def reload_routes_unless_loaded
          self.reloads += 1
          reload_result
        end
      end

      class PostsController < ActionController::Base
        def index
          head :ok
        end

        def show
          head :ok
        end
      end

      setup do
        @previous_application = Rails.application
        @application = FakeApplication.new(0, true)
        Rails.application = @application
      end

      teardown do
        Rails.application = @previous_application
      end

      test "lazy route set reloads before route set entry points" do
        routes = LazyRouteSet.new
        assert_instance_of LazyRouteSet::NamedRouteCollection, routes.named_routes

        routes.draw do
          root to: ->(_env) { [200, {}, ["root"]] }
          get "/posts", to: "rails/engine/lazy_route_set_public_contract_test/posts#index", as: :posts
          get "/posts/:id", to: "rails/engine/lazy_route_set_public_contract_test/posts#show", as: :post
        end

        assert_operator @application.reloads, :>=, 1
        assert routes.routes.any?
        assert routes.polymorphic_mappings.empty?
        expected_parameters = { controller: "rails/engine/lazy_route_set_public_contract_test/posts", action: "index" }
        assert_equal expected_parameters, routes.recognize_path("/posts")

        request = ActionDispatch::Request.new(::Rack::MockRequest.env_for("/posts"))
        assert_equal expected_parameters, routes.recognize_path_with_request(request, "/posts", {})

        status, _headers, body = routes.call(::Rack::MockRequest.env_for("/"))
        assert_equal 200, status
        assert_equal ["root"], body.each.to_a

        original_application_method = Rails.method(:application)
        begin
          Rails.define_singleton_method(:application) { nil }
          status, _headers, body = routes.call(::Rack::MockRequest.env_for("/"))
          assert_equal 200, status
          assert_equal ["root"], body.each.to_a
        ensure
          Rails.define_singleton_method(:application, original_application_method)
        end

        path, extras = routes.generate_extras(controller: "rails/engine/lazy_route_set_public_contract_test/posts", action: "show", id: "1", trailing: "kept")
        assert_equal "/posts/1", path
        assert_equal [ :trailing ], extras

        assert_not routes.named_routes.route_defined?("missing_route")
      end

      test "url helper proxy methods reload routes before delegating" do
        routes = LazyRouteSet.new
        routes.draw do
          get "/posts/:id", to: "rails/engine/lazy_route_set_public_contract_test/posts#show", as: :post
          direct(:direct_post) { |id| "/direct/posts/#{id}" }
        end

        helpers = routes.url_helpers

        assert_equal "/posts/1", helpers.url_for(controller: "rails/engine/lazy_route_set_public_contract_test/posts", action: "show", id: "1", only_path: true)
        assert_equal "http://example.test/posts/1", helpers.full_url_for(controller: "rails/engine/lazy_route_set_public_contract_test/posts", action: "show", id: "1", host: "example.test")
        assert_equal "/direct/posts/2", helpers.route_for(:direct_post, 2)
        assert_includes [true, false], helpers.optimize_routes_generation?
      end

      test "missing helper methods retry after reload and then fall back" do
        routes = LazyRouteSet.new
        path_helpers = routes.named_routes.path_helpers_module
        object = Object.new.extend(path_helpers)

        @application.reload_result = false

        assert_raises(NoMethodError) { object.missing_contract_path }
        assert_not object.respond_to?(:missing_contract_path)
      end
    end
  end
end
