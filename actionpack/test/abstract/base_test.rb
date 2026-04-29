# frozen_string_literal: true

require "abstract_unit"

class AbstractControllerBaseTest < ActiveSupport::TestCase
  class AbstractParent < AbstractController::Base
    abstract!

    def inherited_action
      self.response_body = "inherited"
    end
  end

  class ConcreteController < AbstractParent
    attr_reader :processed_args

    def index
      self.response_body = "index"
    end

    def with_args(*args)
      @processed_args = args
      self.response_body = args
    end

    def action_missing(name, *args)
      @processed_args = args
      self.response_body = "missing #{name}"
    end

    def public_helper
      "helper"
    end

    private
      def private_action
        "private"
      end
  end

  class ControllerWithoutMissing < AbstractParent
    def index
      self.response_body = "index"
    end
  end

  setup do
    ControllerWithoutMissing.clear_action_methods!
    AbstractParent.clear_action_methods!
    ConcreteController.clear_action_methods!
  end

  test "abstract controller eager load skips abstract descendants" do
    abstract_controller = Class.new(AbstractController::Base) do
      abstract!
    end
    concrete_controller = Class.new(AbstractController::Base)
    loaded = []

    AbstractController::Caching.stub(:eager_load!, -> { loaded << :caching }) do
      AbstractController::Base.stub(:descendants, [abstract_controller, concrete_controller]) do
        concrete_controller.stub(:eager_load!, -> { loaded << :concrete }) do
          abstract_controller.stub(:eager_load!, -> { loaded << :abstract }) do
            AbstractController.eager_load!
          end
        end
      end
    end

    assert_equal [ :caching, :concrete ], loaded
  end

  test "abstract class marker and controller path" do
    assert AbstractParent.abstract?
    assert_equal true, AbstractParent.abstract
    assert_not ConcreteController.abstract?
    assert_equal "abstract_controller_base_test/concrete", ConcreteController.controller_path
    assert_equal ConcreteController.controller_path, ConcreteController.new.controller_path
    assert_nil Class.new(AbstractController::Base).controller_path
  end

  test "config is inheritable and available on instances" do
    original_config = ConcreteController.config
    ConcreteController.config = ActiveSupport::InheritableOptions.new(original_config)
    ConcreteController.configure { |config| config.example = :configured }

    controller = ConcreteController.new
    controller.config = ActiveSupport::InheritableOptions.new(ConcreteController.config)
    controller.config.instance_value = :custom

    assert_equal :configured, ConcreteController.config.example
    assert_equal :configured, controller.config.example
    assert_equal :custom, controller.config.instance_value
    assert_not_same ConcreteController.config, controller.config
  ensure
    ConcreteController.config = original_config
  end

  test "eager_load warms cached action methods" do
    ConcreteController.clear_action_methods!

    assert_nil ConcreteController.eager_load!
    assert_includes ConcreteController.action_methods, "index"
  end

  test "action methods exclude abstract and private methods and refresh when methods are added" do
    assert_includes ConcreteController.action_methods, "index"
    assert_includes ConcreteController.action_methods, "with_args"
    assert_not_includes ConcreteController.action_methods, "inherited_action"
    assert_not_includes ConcreteController.action_methods, "private_action"

    ConcreteController.class_eval do
      def dynamically_added_action
        self.response_body = "dynamic"
      end
    end

    assert_includes ConcreteController.action_methods, "dynamically_added_action"
  ensure
    ConcreteController.class_eval { remove_method :dynamically_added_action if method_defined?(:dynamically_added_action) }
    ConcreteController.clear_action_methods!
  end

  test "process dispatches actions and records response state" do
    controller = ConcreteController.new

    controller.process(:index)
    assert_equal "index", controller.action_name
    assert_equal "index", controller.response_body
    assert_equal "index", controller.performed?
    assert_equal ConcreteController.action_methods, controller.action_methods
  end

  test "process passes arguments and resets response body for each dispatch" do
    controller = ConcreteController.new

    controller.response_body = "previous"
    controller.process(:with_args, 1, 2)

    assert_equal [ 1, 2 ], controller.processed_args
    assert_equal [ 1, 2 ], controller.response_body
    assert_equal "with_args", controller.action_name
  end

  test "available action uses action methods, action_missing, and valid action names" do
    controller = ConcreteController.new

    assert_equal "index", controller.available_action?("index")
    assert_equal "_handle_action_missing", controller.available_action?("unknown")
    assert_nil ControllerWithoutMissing.new.available_action?("unknown")
    assert_equal false, controller.available_action?("admin/users")

    controller.process(:unknown, :argument)
    assert_equal "missing unknown", controller.response_body
    assert_equal [ :argument ], controller.processed_args
  end

  test "missing invalid action raises action not found" do
    error = assert_raises(AbstractController::ActionNotFound) do
      ConcreteController.new.process("admin/users")
    end

    assert_equal ConcreteController, error.controller.class
    assert_equal "admin/users", error.action
    assert_match "could not be found", error.message
  end

  test "formats and supports_path accessors" do
    controller = ConcreteController.new
    controller.formats = [ :html ]

    assert_equal [ :html ], controller.formats
    assert ConcreteController.supports_path?
  end
end
