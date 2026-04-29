# frozen_string_literal: true

require "abstract_unit"

module AbstractController
  module Testing
    class UrlForController < AbstractController::Base
      include AbstractController::UrlFor

      def index; end
    end

    class RoutedUrlForController < AbstractController::Base
      include AbstractController::UrlFor

      def index; end
      def account_path; end

      def self._routes
        @routes ||= Struct.new(:named_routes).new(Struct.new(:helper_names).new([ "account_path" ]))
      end
    end

    class UrlForTest < ActiveSupport::TestCase
      def setup
        UrlForController.clear_action_methods!
        RoutedUrlForController.clear_action_methods!
      end

      test "instance routes raises until routing helpers are included" do
        error = assert_raises RuntimeError do
          UrlForController.new._routes
        end

        assert_includes error.message, "you must include routing helpers explicitly"
      end

      test "class routes default to nil" do
        assert_nil UrlForController._routes
      end

      test "action methods fall back to superclass action methods without routes" do
        assert_includes UrlForController.action_methods, "index"
      end

      test "action methods exclude named route helper names when routes are present" do
        assert_includes RoutedUrlForController.action_methods, "index"
        assert_not_includes RoutedUrlForController.action_methods, "account_path"
      end
    end
  end
end
