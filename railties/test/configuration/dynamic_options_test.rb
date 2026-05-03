# frozen_string_literal: true

require "active_support"
require "active_support/test_case"
require "active_support/testing/autorun"
require "rails/railtie/configuration"

module RailtiesTest
  class DynamicOptionsTest < ActiveSupport::TestCase
    setup do
      @config = Rails::Railtie::Configuration.dup.new
      @config.class.class_variable_set(:@@options, {})
    end

    test "arbitrary keys can be set, reset, and read" do
      @config.foo = 1
      assert_equal 1, @config.foo

      @config.foo = 2
      assert_equal 2, @config.foo
    end

    test "raises NoMethodError if the key is unset and the method does not exist" do
      assert_raises(NoMethodError) do
        @config.unset_key
      end
    end

    test "raises NoMethodError with an informative message if assigning to an existing method" do
      error = assert_raises(NoMethodError) do
        @config.eager_load_namespaces = 1
      end

      assert_match(/Cannot assign to `eager_load_namespaces`, it is a configuration method/, error.message)
    end

    test "shared collections are lazily initialized and memoized" do
      assert_empty @config.class.eager_load_namespaces
      assert_empty @config.eager_load_namespaces
      assert_empty @config.watchable_files
      assert_empty @config.watchable_dirs
      assert_kind_of Rails::Configuration::MiddlewareStackProxy, @config.app_middleware

      @config.watchable_files << "config/routes.rb"
      @config.watchable_dirs["app/models"] = ["rb"]
      @config.eager_load_namespaces << RailtiesTest
      @config.app_middleware.use :middleware_contract

      assert_equal ["config/routes.rb"], @config.watchable_files
      assert_equal({ "app/models" => ["rb"] }, @config.watchable_dirs)
      assert_includes @config.eager_load_namespaces, RailtiesTest
      assert_same @config.app_middleware, @config.app_middleware
    end

    test "app_generators yields and memoizes generator configuration" do
      yielded = nil

      generators = @config.app_generators do |g|
        yielded = g
        g.orm :sequel
      end

      assert_same generators, yielded
      assert_same generators, @config.app_generators
      assert_equal :sequel, generators.orm
    end

    test "initialization hooks register blocks that receive the application" do
      with_load_hooks_restored do
        events = []

        @config.before_configuration { |app| events << [:before_configuration, app] }
        @config.before_initialize { |app| events << [:before_initialize, app] }
        @config.before_eager_load { |app| events << [:before_eager_load, app] }
        @config.after_initialize { |app| events << [:after_initialize, app] }
        @config.after_routes_loaded { |app| events << [:after_routes_loaded, app] }

        app = Object.new
        ActiveSupport.run_load_hooks(:before_configuration, app)
        ActiveSupport.run_load_hooks(:before_initialize, app)
        ActiveSupport.run_load_hooks(:before_eager_load, app)
        ActiveSupport.run_load_hooks(:after_initialize, app)
        ActiveSupport.run_load_hooks(:after_routes_loaded, app)

        assert_equal [
          [:before_configuration, app],
          [:before_initialize, app],
          [:before_eager_load, app],
          [:after_initialize, app],
          [:after_routes_loaded, app]
        ], events
      end
    end

    test "to_prepare stores blocks and ignores nil" do
      block = -> {}

      assert_empty @config.to_prepare_blocks
      assert_nil @config.to_prepare
      @config.to_prepare(&block)

      assert_equal [block], @config.to_prepare_blocks
      assert_same @config.to_prepare_blocks, @config.to_prepare_blocks
    end

    private
      def with_load_hooks_restored
        original_hooks = ActiveSupport.instance_variable_get(:@load_hooks).transform_values(&:dup)
        original_loaded = ActiveSupport.instance_variable_get(:@loaded).transform_values(&:dup)
        yield
      ensure
        ActiveSupport.instance_variable_set(:@load_hooks, original_hooks)
        ActiveSupport.instance_variable_set(:@loaded, original_loaded)
      end
  end
end
