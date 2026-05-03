# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/rails/resource_route/resource_route_generator"

class ResourceRouteGeneratorPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  tests Rails::Generators::ResourceRouteGenerator

  test "adds pluralized resource route with namespace" do
    generator = generator_class.new(["admin/post"], actions: [])
    routes = []
    generator.define_singleton_method(:route) do |*args, **kwargs|
      routes << [args, kwargs]
    end

    generator.add_resource_route

    assert_equal [[ ["resources :posts"], { namespace: ["admin"] } ]], routes
  end

  test "does not add resource route when actions are provided" do
    generator = generator_class.new(["admin/post"], actions: ["index"])
    generator.define_singleton_method(:route) do |*|
      flunk "route should not be called when actions are present"
    end

    assert_nil generator.add_resource_route
  end
end
