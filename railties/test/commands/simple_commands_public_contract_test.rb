# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/destroy/destroy_command"
require "rails/commands/dev/dev_command"
require "rails/commands/devcontainer/devcontainer_command"

class SimpleCommandsPublicContractTest < ActiveSupport::TestCase
  setup do
    @removed_constants = {}
    @replaced_constants = {}
  end

  teardown do
    restore_constants
  end

  test "destroy help boots application loads generators and prints generator help" do
    command = Rails::Command::DestroyCommand.new([], [])
    calls = []
    command.define_singleton_method(:boot_application!) { calls << :boot_application }
    command.define_singleton_method(:load_generators) { calls << :load_generators }

    with_singleton_method(Rails::Generators, :help, ->(name) { calls << [ :help, name ] }) do
      command.help
    end

    assert_equal [ :boot_application, :load_generators, [ :help, "destroy" ] ], calls
  end

  test "destroy perform shows help without generator and revokes named generator with remaining args" do
    help_command = Rails::Command::DestroyCommand.new([], [])
    help_command.define_singleton_method(:help) { :helped }

    assert_equal :helped, help_command.perform

    command = Rails::Command::DestroyCommand.new(["model", "Post", "title:string"], [])
    calls = []
    command.define_singleton_method(:boot_application!) { calls << :boot_application }
    command.define_singleton_method(:load_generators) { calls << :load_generators }

    with_singleton_method(Rails::Command, :root, -> { Pathname.new("/tmp/app") }) do
      with_singleton_method(Rails::Generators, :invoke, ->(*args, **options) { calls << [ args, options ] }) do
        command.perform
      end
    end

    assert_equal :boot_application, calls[0]
    assert_equal :load_generators, calls[1]
    assert_equal [["model", ["Post", "title:string"]], { behavior: :revoke, destination_root: Pathname.new("/tmp/app") }], calls[2]
  end

  test "dev cache delegates to dev caching" do
    called = false
    with_singleton_method(Rails::DevCaching, :enable_by_file, -> { called = true }) do
      Rails::Command::DevCommand.new([], []).cache
    end

    assert called
  end

  test "devcontainer perform reports derived options and invokes generator" do
    replace_constant(:ActiveRecord, fake_active_record("mysql2"))
    replace_constant(:ActiveStorage, Module.new)
    replace_constant(:ActionCable, Module.new)
    remove_constant(:SolidCable)
    remove_constant(:ActiveJob)
    remove_constant(:SolidQueue)

    generator_calls = []
    command = Rails::Command::DevcontainerCommand.new([], [])
    command.define_singleton_method(:boot_application!) { generator_calls << :boot_application }
    app = fake_application("demo_application", "mysql2")

    with_rails_application(app) do
      with_rails_root(Pathname.new("/tmp/demo")) do
        with_file_exist({ "test/application_system_test_case.rb" => true, ".node-version" => true, "config/deploy.yml" => false }) do
          generator = fake_generator(generator_calls)
          with_singleton_method(Rails::Generators::DevcontainerGenerator, :new, ->(args, options) { generator_calls << [ args, options ]; generator }) do
            output = capture(:stdout) { command.perform }
            assert_includes output, "app_name: demo"
          end
        end
      end
    end

    options = generator_calls[1][1]
    assert_equal({
      app_name: "demo",
      app_folder: "demo",
      database: "mysql",
      active_storage: true,
      redis: true,
      system_test: true,
      node: true,
      kamal: false,
    }, options)
    assert_equal :invoke_all, generator_calls[2]
  end

  test "devcontainer options reflect absent frameworks and non mysql database" do
    remove_constant(:ActiveStorage)
    replace_constant(:ActiveRecord, fake_active_record("sqlite3"))
    replace_constant(:ActionCable, Module.new)
    replace_constant(:SolidCable, Module.new)
    replace_constant(:ActiveJob, Module.new)
    replace_constant(:SolidQueue, Module.new)

    command = Rails::Command::DevcontainerCommand.new([], [])
    app = fake_application("sample_application", "sqlite3")

    with_rails_application(app) do
      with_rails_root(Pathname.new("/tmp/sample")) do
        with_file_exist({ "test/application_system_test_case.rb" => false, ".node-version" => false, "config/deploy.yml" => true }) do
          options = command.send(:devcontainer_options)
          assert_equal "sqlite3", options[:database]
          assert_equal false, options[:active_storage]
          assert_equal false, options[:redis]
          assert_equal false, options[:system_test]
          assert_equal false, options[:node]
          assert_equal true, options[:kamal]
        end
      end
    end
  end

  test "devcontainer options omit database when active record is absent" do
    remove_constant(:ActiveRecord)
    remove_constant(:ActiveStorage)
    remove_constant(:ActionCable)
    remove_constant(:ActiveJob)

    command = Rails::Command::DevcontainerCommand.new([], [])
    app = fake_application("plain_application", "sqlite3")

    with_rails_application(app) do
      with_rails_root(Pathname.new("/tmp/plain")) do
        with_file_exist({}) do
          assert_equal false, command.send(:devcontainer_options)[:database]
        end
      end
    end
  end

  private
    def fake_application(railtie_name, adapter)
      Struct.new(:railtie_name, :adapter) do
        def config = self
        def database_configuration = {}
      end.new(railtie_name, adapter)
    end

    def fake_active_record(adapter)
      connection_config = Struct.new(:adapter).new(adapter)
      base = Class.new
      base.define_singleton_method(:connection_db_config) { connection_config }
      mod = Module.new
      mod.const_set(:Base, base)
      mod
    end

    def fake_generator(calls)
      Struct.new(:calls) do
        def invoke_all = calls << :invoke_all
      end.new(calls)
    end

    def with_singleton_method(object, name, replacement)
      singleton = class << object; self; end
      original = object.method(name) if object.respond_to?(name)
      had_own_method = singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.send(:remove_method, name) if had_own_method
      singleton.define_method(name, replacement)
      yield
    ensure
      singleton.send(:remove_method, name) if singleton.instance_methods(false).include?(name) || singleton.private_instance_methods(false).include?(name)
      singleton.define_method(name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if original && had_own_method
    end

    def with_rails_application(app)
      singleton = class << Rails; self; end
      original = Rails.method(:application)
      singleton.define_method(:application) { app }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_rails_root(root)
      singleton = class << Rails; self; end
      original = Rails.method(:root)
      singleton.define_method(:root) { root }
      yield
    ensure
      singleton.send(:remove_method, :root) if singleton.method_defined?(:root)
      singleton.define_method(:root) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_file_exist(results)
      original = File.method(:exist?)
      File.singleton_class.define_method(:exist?) { |path| results.fetch(path, false) }
      yield
    ensure
      File.singleton_class.send(:remove_method, :exist?) if File.singleton_class.method_defined?(:exist?)
      File.singleton_class.define_method(:exist?) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def replace_constant(name, value)
      @replaced_constants[name] = Object.const_get(name) if Object.const_defined?(name) && !@replaced_constants.key?(name)
      @removed_constants.delete(name)
      Object.send(:remove_const, name) if Object.const_defined?(name)
      Object.const_set(name, value)
    end

    def remove_constant(name)
      return unless Object.const_defined?(name)
      @removed_constants[name] = Object.const_get(name) unless @replaced_constants.key?(name) || @removed_constants.key?(name)
      Object.send(:remove_const, name)
    end

    def restore_constants
      (@replaced_constants.keys | @removed_constants.keys).each do |name|
        Object.send(:remove_const, name) if Object.const_defined?(name)
        original = @replaced_constants.fetch(name) { @removed_constants[name] }
        Object.const_set(name, original) if original
      end
    end
end
