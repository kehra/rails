# frozen_string_literal: true

require "abstract_unit"

module AbstractController
  module Testing
    class RenderingController < AbstractController::Base
      include AbstractController::Rendering

      attr_reader :html_content_type_set, :rendered_content_type, :vary_header_set

      def render_to_body(options = {})
        return options unless options.respond_to?(:[])

        options[:body] || "rendered body"
      end

      def _set_html_content_type
        @html_content_type_set = true
      end

      def _set_rendered_content_type(format)
        @rendered_content_type = format
      end

      def _set_vary_header
        @vary_header_set = true
      end
    end

    class PermittedRenderParameters
      def initialize(permitted)
        @permitted = permitted
      end

      def permitted?
        @permitted
      end
    end

    class RenderingTest < ActiveSupport::TestCase
      def setup
        @controller = RenderingController.new
      end

      test "render stores the rendered body and rendered content type" do
        @controller.render body: "hello"

        assert_equal "hello", @controller.response_body
        assert_equal Mime[:text], @controller.rendered_content_type
        assert @controller.vary_header_set
      end

      test "render with html option sets html content type" do
        @controller.render html: "<strong>hello</strong>"

        assert_equal "rendered body", @controller.response_body
        assert @controller.html_content_type_set
        assert @controller.vary_header_set
      end

      test "render_to_string returns body without assigning response body" do
        assert_equal "hello", @controller.render_to_string(body: "hello")
        assert_nil @controller.response_body
      end

      test "render_to_string with a non-hash action uses explicit options" do
        assert_equal "hello", @controller.render_to_string("show", body: "hello")
      end

      test "render_to_body default implementation returns nil" do
        abstract_controller = Class.new(AbstractController::Base) do
          include AbstractController::Rendering
        end.new

        assert_nil abstract_controller.render_to_body({})
      end

      test "rendered_format defaults to text" do
        assert_equal Mime[:text], @controller.rendered_format
      end

      test "view_assigns excludes protected ivars" do
        @controller.instance_variable_set(:@visible, "yes")
        @controller.instance_variable_set(:@_action_name, "hidden")

        assert_equal({ "visible" => "yes" }, @controller.view_assigns)
      end

      test "double render error uses the default message unless overridden" do
        assert_equal AbstractController::DoubleRenderError::DEFAULT_MESSAGE, AbstractController::DoubleRenderError.new.message
        assert_equal "custom", AbstractController::DoubleRenderError.new("custom").message
      end

      test "normalize render accepts permitted parameter objects" do
        parameters = PermittedRenderParameters.new(true)

        assert_same parameters, @controller.render_to_string(parameters)
      end

      test "normalize render rejects unpermitted parameter objects" do
        assert_raises ArgumentError do
          @controller.render_to_string(PermittedRenderParameters.new(false))
        end
      end
    end
  end
end
