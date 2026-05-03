# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/command/base"
require "rails/command/environment_argument"
require "tmpdir"

class CommandEnvironmentArgumentPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_env = ENV.to_hash
    @original_dir = Dir.pwd
    @root = Dir.mktmpdir("command-environment-argument")
    FileUtils.mkdir_p(File.join(@root, "config/environments"))
    %w[development production test custom].each do |name|
      FileUtils.touch(File.join(@root, "config/environments/#{name}.rb"))
    end
    Dir.chdir(@root)
  end

  teardown do
    ENV.replace(@original_env)
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@root)
  end

  test "default environment comes from command environment and is marked unspecified" do
    with_command_environment("custom") do
      command = environment_command.new([], {}, {})

      assert_equal "custom", command.options[:environment]
      assert_equal "custom", command.send(:environment)
      assert_not command.send(:environment_specified?)
      assert_equal %w[custom development production test], command.send(:available_environments).sort

      command.send(:environment=, "manual")
      assert_equal "manual", command.send(:environment)
    end
  end

  test "explicit environment is preserved or expanded and require_application sets rails env" do
    explicit = environment_command.new([], { environment: "custom" }, {})
    assert explicit.send(:environment_specified?)
    assert_equal "custom", explicit.options[:environment]

    expanded = environment_command.new([], { environment: "prod" }, {})
    assert expanded.send(:environment_specified?)
    assert_equal "production", expanded.options[:environment]
    expanded.send(:require_application!)
    assert_equal "production", ENV["RAILS_ENV"]

    unknown = environment_command.new([], { environment: "qa" }, {})
    assert_equal "qa", unknown.options[:environment]
  end

  private
    def environment_command
      @environment_command ||= Class.new(Rails::Command::Base) do
        include Rails::Command::EnvironmentArgument
        def self.name = "Rails::Command::EnvironmentContractCommand"
        def perform; end
      end
    end

    def with_command_environment(environment)
      singleton = class << Rails::Command; self; end
      original = Rails::Command.method(:environment)
      singleton.define_method(:environment) { environment }
      yield
    ensure
      singleton.send(:remove_method, :environment) if singleton.method_defined?(:environment)
      singleton.define_method(:environment) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
