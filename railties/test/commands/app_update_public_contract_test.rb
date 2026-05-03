# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/command/base"
require "rails/commands/app/update_command"
require "tmpdir"

class AppUpdateCommandPublicContractTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("app-update-command"))
    FileUtils.mkdir_p(@root.join("config"))
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "perform silences deprecators runs update steps and prints upgrade guide" do
    command = Rails::Command::App::UpdateCommand.new([], {}, {})
    events = []
    fake_generator = FakeAppGenerator.new(events)
    application = fake_application(api_only: true, system_tests: nil, name: "Demo::Application")

    with_rails_root_and_application(@root, application) do
      with_app_generator(fake_generator) do
        command.define_singleton_method(:say) { |message| events << [ :say, message ] }
        command.perform
      end
    end

    assert_equal true, application.deprecators.silenced
    assert_includes events, :create_boot_file
    assert_includes events, :update_config_files
    assert_includes events, :update_bin_files
    assert_includes events, :create_public_files
    assert_includes events, :update_active_storage
    assert events.any? { |event| event.is_a?(Array) && event.first == :say && event.last.include?("Rails upgrade guide") }
  end

  test "subcommands delegate to app generator and app generator validates missing application file" do
    events = []
    fake_generator = FakeAppGenerator.new(events)
    application = fake_application(api_only: false, system_tests: :rspec, name: "SampleApp::Application")
    command = Rails::Command::App::UpdateCommand.new([], { force: true }, {})

    with_rails_root_and_application(@root, application) do
      with_app_generator(fake_generator) do
        command.configs
        command.bin
        command.public_directory
        command.active_storage
      end
    end

    assert_includes events, :valid_const
    assert_equal [ :valid_const, :create_boot_file, :update_config_files, :update_bin_files, :create_public_files, :update_active_storage ], events
  end

  test "app generator skips validation when application file exists and generator options reflect application" do
    events = []
    fake_generator = FakeAppGenerator.new(events)
    application = fake_application(api_only: true, system_tests: nil, name: "DemoApp::Application")
    @root.join("config/application.rb").write("# app")
    command = Rails::Command::App::UpdateCommand.new([], { pretend: true }, {})

    with_rails_root_and_application(@root, application) do
      with_app_generator(fake_generator) do
        command.send(:app_generator)
      end
    end

    assert_not_includes events, :valid_const
    options = fake_generator.options
    assert_equal true, options[:api]
    assert_equal true, options[:update]
    assert_equal "demo_app", options[:name]
    assert_equal true, options[:skip_system_test]
    assert_nil options[:pretend]
    assert_equal @root, fake_generator.destination_root
  end

  test "asset pipeline and skip gem helpers expose private option decisions" do
    command = Rails::Command::App::UpdateCommand.new([], {}, {})

    assert_nil command.send(:asset_pipeline)
    with_constant(:Propshaft, Module.new) do
      Propshaft.const_set(:Railtie, Class.new)
      assert_equal "propshaft", command.send(:asset_pipeline)
    end

    assert_equal false, command.send(:skip_gem?, "rake")
    assert_equal true, command.send(:skip_gem?, "missing-rails-command-update-contract-gem")
  end

  private
    class FakeAppGenerator
      attr_reader :args, :options, :destination_root

      def initialize(events)
        @events = events
      end

      def capture(args, options, destination_root:)
        @args = args
        @options = options
        @destination_root = destination_root
        self
      end

      def create_boot_file = @events << :create_boot_file
      def update_config_files = @events << :update_config_files
      def update_bin_files = @events << :update_bin_files
      def create_public_files = @events << :create_public_files
      def update_active_storage = @events << :update_active_storage

      private
        def valid_const? = @events << :valid_const
    end

    def fake_application(api_only:, system_tests:, name:)
      config = ActiveSupport::OrderedOptions.new
      config.api_only = api_only
      config.generators = ActiveSupport::OrderedOptions.new
      config.generators.system_tests = system_tests
      deprecators = ActiveSupport::OrderedOptions.new
      app_class = Class.new
      app_class.define_singleton_method(:name) { name }
      Object.new.tap do |app|
        app.define_singleton_method(:config) { config }
        app.define_singleton_method(:deprecators) { deprecators }
        app.define_singleton_method(:class) { app_class }
      end
    end

    def with_rails_root_and_application(root, application)
      singleton = class << Rails; self; end
      originals = {}
      [ :root, :application ].each { |name| originals[name] = Rails.method(name) if Rails.respond_to?(name) }
      singleton.define_method(:root) { root }
      singleton.define_method(:application) { application }
      yield
    ensure
      [ :root, :application ].each do |name|
        singleton.send(:remove_method, name) if singleton.method_defined?(name)
        if originals[name]
          original = originals[name]
          singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
        end
      end
    end

    def with_app_generator(fake_generator)
      singleton = class << Rails::Generators::AppGenerator; self; end
      original = Rails::Generators::AppGenerator.method(:new)
      singleton.define_method(:new) do |args, options, destination_root:|
        fake_generator.capture(args, options, destination_root: destination_root)
      end
      yield
    ensure
      singleton.send(:remove_method, :new) if singleton.method_defined?(:new)
      singleton.define_method(:new) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_constant(name, value)
      existed = Object.const_defined?(name)
      original = Object.const_get(name) if existed
      Object.send(:remove_const, name) if existed
      Object.const_set(name, value)
      yield
    ensure
      Object.send(:remove_const, name) if Object.const_defined?(name)
      Object.const_set(name, original) if existed
    end
end
