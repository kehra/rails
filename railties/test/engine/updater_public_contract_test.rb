# frozen_string_literal: true

require "abstract_unit"
require "rails/engine/updater"

module Rails
  class Engine
    class UpdaterPublicContractTest < ActiveSupport::TestCase
      setup do
        @root = Dir.mktmpdir("rails-engine-updater-public-contract")
        @previous_engine_root = Object.const_get(:ENGINE_ROOT) if Object.const_defined?(:ENGINE_ROOT)
        Object.send(:remove_const, :ENGINE_ROOT) if Object.const_defined?(:ENGINE_ROOT)
        Object.const_set(:ENGINE_ROOT, @root)
        remove_generator
      end

      teardown do
        remove_generator
        Object.send(:remove_const, :ENGINE_ROOT) if Object.const_defined?(:ENGINE_ROOT)
        Object.const_set(:ENGINE_ROOT, @previous_engine_root) if defined?(@previous_engine_root)
        FileUtils.rm_rf(@root)
      end

      test "generator memoizes an engine plugin generator rooted at ENGINE_ROOT" do
        generator = Updater.generator

        assert_instance_of Rails::Generators::PluginGenerator, generator
        assert_same generator, Updater.generator
        assert_equal @root, generator.destination_root
        assert generator.options[:engine]
      end

      test "run dispatches public actions to the generator" do
        fake_generator = Object.new
        fake_generator.define_singleton_method(:contract_action) { :ran }
        Updater.instance_variable_set(:@generator, fake_generator)

        assert_equal :ran, Updater.run(:contract_action)
      end

      private
        def remove_generator
          Updater.remove_instance_variable(:@generator) if Updater.instance_variable_defined?(:@generator)
        end
    end
  end
end
