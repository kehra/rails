# frozen_string_literal: true

require "abstract_unit"
require "rails/railtie"

class RailtiePublicContractTest < ActiveSupport::TestCase
  setup do
    @constants = []
  end

  teardown do
    @constants.reverse_each do |name|
      Object.send(:remove_const, name) if Object.const_defined?(name)
    end
  end

  test "class accessors register hooks configure instance and expose subclasses" do
    parent = railtie_const(:PublicContractParent)
    child = railtie_const(:PublicContractChild, parent)
    abstract = railtie_const(:PublicContractAbstract)
    abstract.define_singleton_method(:name) { "Rails::Engine" }

    assert Rails::Railtie.abstract_railtie?
    assert_not child.abstract_railtie?
    assert_includes Rails::Railtie.subclasses, parent
    assert_not_includes Rails::Railtie.subclasses, abstract

    assert_equal "public_contract_child", child.railtie_name
    assert_equal "manual_name", child.railtie_name("manual_name")
    assert_equal "manual_name", child.instance.railtie_name
    assert_same child.instance, child.instance
    assert_same child.config, child.instance.config

    child.configure do
      config.public_contract_value = :configured
    end
    assert_equal :configured, child.config.public_contract_value

    events = []
    child.rake_tasks { |app| events << [ :tasks, app ] }
    child.console { |app| events << [ :console, app ] }
    child.runner { |app| events << [ :runner, app ] }
    child.generators { |app| events << [ :generators, app ] }
    child.server { |app| events << [ :server, app ] }

    assert_equal 1, child.rake_tasks.length
    assert_equal 1, child.console.length
    assert_equal 1, child.runner.length
    assert_equal 1, child.generators.length
    assert_equal 1, child.server.length

    child.instance.send(:run_console_blocks, :console_app)
    child.instance.send(:run_generators_blocks, :generators_app)
    child.instance.send(:run_runner_blocks, :runner_app)
    with_rake_dsl do
      child.instance.send(:run_tasks_blocks, :tasks_app)
    end
    child.instance.send(:run_server_blocks, :server_app)

    assert_includes events, [ :console, :console_app ]
    assert_includes events, [ :generators, :generators_app ]
    assert_includes events, [ :runner, :runner_app ]
    assert_includes events, [ :tasks, :tasks_app ]
    assert_includes events, [ :server, :server_app ]
  end

  test "load hook guard logs raises or stays quiet based on application configuration" do
    log_component = :public_contract_log_component
    raise_component = :public_contract_raise_component
    noop_component = :public_contract_noop_component
    logger = CapturingLogger.new

    with_rails_application_stub(eager_load: false, initialized: false, action: :log, logger: logger) do
      Rails::Railtie.guard_load_hooks(log_component)
      ActiveSupport.run_load_hooks(log_component)
    end

    assert_includes logger.messages.join, "public_contract_log_component"
    assert_includes logger.messages.join, "was loaded before application initialization"

    with_rails_application_stub(eager_load: false, initialized: false, action: :raise, logger: logger) do
      Rails::Railtie.guard_load_hooks(raise_component)
      error = assert_raise(LoadError) { ActiveSupport.run_load_hooks(raise_component) }
      assert_includes error.message, "public_contract_raise_component"
    end

    ignored_action_component = :public_contract_ignored_action_component
    quiet_logger = CapturingLogger.new
    with_rails_application_stub(eager_load: false, initialized: false, action: :ignore, logger: quiet_logger) do
      Rails::Railtie.guard_load_hooks(ignored_action_component)
      ActiveSupport.run_load_hooks(ignored_action_component)
    end
    assert_empty quiet_logger.messages

    eager_load_component = :public_contract_eager_load_component
    with_rails_application_stub(eager_load: true, initialized: false, action: :raise, logger: quiet_logger) do
      Rails::Railtie.guard_load_hooks(eager_load_component)
      ActiveSupport.run_load_hooks(eager_load_component)
    end
    assert_empty quiet_logger.messages
  end

  private
    class CapturingLogger
      attr_reader :messages

      def initialize
        @messages = []
      end

      def warn(message)
        @messages << message
      end
    end

    def railtie_const(name, superclass = Rails::Railtie)
      Object.const_set(name, Class.new(superclass)).tap do
        @constants << name
      end
    end

    def with_rake_dsl
      require "rake"
      yield
    ensure
      Object.send(:remove_const, :APP_RAKEFILE) if Object.const_defined?(:APP_RAKEFILE)
    end

    def with_rails_application_stub(eager_load:, initialized:, action:, logger:)
      singleton = class << Rails; self; end
      originals = {}
      [ :application, :configuration, :logger ].each do |name|
        originals[name] = Rails.method(name) if Rails.respond_to?(name)
      end
      application = Object.new
      application.define_singleton_method(:initialized?) { initialized }
      configuration = ActiveSupport::OrderedOptions.new
      configuration.eager_load = eager_load
      configuration.action_on_early_load_hook = action
      singleton.define_method(:application) { application }
      singleton.define_method(:configuration) { configuration }
      singleton.define_method(:logger) { logger }
      yield
    ensure
      [ :application, :configuration, :logger ].each do |name|
        singleton.send(:remove_method, name) if singleton.method_defined?(name)
        if originals[name]
          original = originals[name]
          singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
        end
      end
    end
end
