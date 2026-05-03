# frozen_string_literal: true

require "abstract_unit"
require "rails/railtie/configurable"

module Rails
  class Railtie
    class ConfigurablePublicContractTest < ActiveSupport::TestCase
      test "instance is memoized and class config delegates to it" do
        railtie = build_configurable_class

        assert_same railtie.instance, railtie.instance
        assert_equal :configurable_contract_config, railtie.config
      end

      test "configure evaluates the block on the class" do
        railtie = build_configurable_class

        railtie.configure do
          @configured_by_contract = true

          def self.configured_by_contract?
            @configured_by_contract
          end
        end

        assert railtie.configured_by_contract?
      end

      test "respond_to and missing methods include instance methods and inherited forbids subclasses" do
        railtie = build_configurable_class("ConfigurableContractParent")

        assert railtie.respond_to?(:instance_contract_method)
        assert_not railtie.respond_to?(:missing_contract_method)
        assert_equal :instance_contract, railtie.instance_contract_method

        error = assert_raises(RuntimeError) { Class.new(railtie) }
        assert_equal "You cannot inherit from a Object child", error.message
      end

      private
        def build_configurable_class(name = nil)
          Class.new do
            include Rails::Railtie::Configurable

            define_singleton_method(:name) { name } if name

            def config
              :configurable_contract_config
            end

            def instance_contract_method
              :instance_contract
            end
          end
        end
    end
  end
end
