# frozen_string_literal: true

require "abstract_unit"
require "action_view/rendering"

class ActionViewRenderingPublicApiTest < ActiveSupport::TestCase
  module GreetingHelper
    def greeting_from_helper
      "hello"
    end
  end

  class RouteSetStub
    attr_reader :supports_path

    def url_helpers(supports_path)
      @supports_path = supports_path
      Module.new do
        def routed_helper
          "routed"
        end
      end
    end

    def mounted_helpers
      Module.new do
        def mounted_helper
          "mounted"
        end
      end
    end
  end

  class BaseController
    include ActionView::Rendering

    def self.abstract? = true
    def self.controller_path = "base"
    def self.supports_path? = false

    def action_name = "hello_world"
    def view_assigns = { "headline" => "Hello" }

    def _process_options(options)
      options[:processed_by_test] = true
    end
  end

  class RenderingController < BaseController
    append_view_path File.expand_path("../fixtures", __dir__)

    def self.abstract? = false
    def self.controller_path = "test"
  end

  class ChildController < RenderingController
  end

  class EagerBaseController
    def self.eager_load!
      @eager_loaded = true
    end

    def self.eager_loaded?
      @eager_loaded
    end
  end

  class EagerController < EagerBaseController
    include ActionView::Rendering

    def self.abstract? = true
    def self.controller_path = "eager"
    def self.supports_path? = false
  end

  class RoutesController < RenderingController
    def self._routes = @routes
    def self._routes=(routes)
      @routes = routes
    end

    def self._helpers = @helpers
    def self._helpers=(helpers)
      @helpers = helpers
    end
  end

  test "i18n proxy delegates reads and writes to the original config and lookup context" do
    original = I18n::Config.new
    original.locale = :en
    lookup_context = Struct.new(:locale).new(:en)

    proxy = ActionView::I18nProxy.new(ActionView::I18nProxy.new(original, lookup_context), lookup_context)

    assert_same original, proxy.original_config
    assert_same lookup_context, proxy.lookup_context
    assert_equal :en, proxy.locale

    proxy.locale = :ja
    assert_equal :ja, lookup_context.locale
    assert_equal :en, original.locale
  end

  test "rendering initializes rendered format and exposes a view context" do
    controller = RenderingController.new

    assert_nil controller.rendered_format
    assert_same RenderingController.view_context_class, controller.view_context_class
    assert_kind_of RenderingController.view_context_class, controller.view_context
  end

  test "render_to_body renders templates and records rendered format" do
    controller = RenderingController.new

    body = controller.render_to_body(action: "hello_world", assigns: { "message" => "ignored" }, variant: :phone)

    assert_match "Hello phone", body
    assert_equal :html, controller.rendered_format.to_sym
    assert_equal [:phone], controller.lookup_context.variants
  end

  test "class helpers and routes defaults are nil" do
    assert_nil RenderingController._helpers
    assert_nil RenderingController._routes
  end

  test "build_view_context_class includes routes and helpers" do
    routes = RouteSetStub.new
    RoutesController._routes = routes
    RoutesController._helpers = GreetingHelper
    RoutesController.remove_instance_variable(:@view_context_class) if RoutesController.instance_variable_defined?(:@view_context_class)

    view_context_class = RoutesController.view_context_class
    view = view_context_class.new(RoutesController.new.lookup_context, {}, RoutesController.new)

    assert_equal false, routes.supports_path
    assert_equal "routed", view.routed_helper
    assert_equal "mounted", view.mounted_helper
    assert_equal "hello", view.greeting_from_helper
  ensure
    RoutesController._routes = nil
    RoutesController._helpers = nil
    RoutesController.remove_instance_variable(:@view_context_class) if RoutesController.instance_variable_defined?(:@view_context_class)
  end

  test "child controller can inherit parent view context class" do
    RenderingController.view_context_class
    ChildController.remove_instance_variable(:@view_context_class) if ChildController.instance_variable_defined?(:@view_context_class)

    assert_predicate ChildController, :inherit_view_context_class?
    assert_same RenderingController.view_context_class, ChildController.view_context_class
  end

  test "view context class is rebuilt when the details key view class changes" do
    RenderingController.view_context_class
    ActionView::LookupContext::DetailsKey.clear

    assert RenderingController.view_context_class
  end

  test "eager load builds view context class and returns nil" do
    EagerController.remove_instance_variable(:@view_context_class) if EagerController.instance_variable_defined?(:@view_context_class)

    assert_nil EagerController.eager_load!
    assert_predicate EagerController, :eager_loaded?
    assert EagerController.instance_variable_defined?(:@view_context_class)
  end
end
