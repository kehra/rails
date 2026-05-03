# frozen_string_literal: true

require "abstract_unit"
require "rails/command/actions"
require "tmpdir"

class CommandActionsPublicContractTest < ActiveSupport::TestCase
  setup do
    @original_dir = Dir.pwd
    @original_features = $LOADED_FEATURES.dup
    @temporary_constants = []
  end

  teardown do
    Dir.chdir(@original_dir)
    @temporary_constants.reverse_each { |name| remove_constant(name) }
    $LOADED_FEATURES.replace(@original_features)
  end

  test "application actions require boot initialize tasks generators and application directory" do
    events = []
    root = Pathname.new(Dir.mktmpdir("command-actions-app"))
    nested = root.join("nested")
    FileUtils.mkdir_p(root.join("config"))
    FileUtils.mkdir_p(nested)
    app_path = root.join("config/application.rb")
    app_path.write("$command_actions_required ||= []; $command_actions_required << :app\n")
    set_constant(:APP_PATH, app_path.to_s)
    load_actions_file

    application = Object.new
    application.define_singleton_method(:require_environment!) { events << :require_environment }
    application.define_singleton_method(:initialize!) { |group| events << [ :initialize, group ] }
    application.define_singleton_method(:load_tasks) { events << :load_tasks }
    application.define_singleton_method(:load_generators) { events << :load_generators }

    with_rails_application(application) do
      actions = action_object

      Dir.chdir(nested)
      actions.set_application_directory!
      assert_equal root.to_s, Dir.pwd

      FileUtils.touch(root.join("config.ru"))
      Dir.chdir(root)
      actions.set_application_directory!
      assert_equal root.to_s, Dir.pwd

      actions.require_application!
      actions.boot_application!
      actions.load_environment_config!
      remove_constant(:APP_PATH)
      actions.require_application!
      actions.boot_application!
      actions.load_environment_config!
      set_constant(:APP_PATH, app_path.to_s)
      actions.load_tasks
      actions.load_generators
    end

    assert_operator $command_actions_required.count(:app), :>=, 1
    assert_includes events, :require_environment
    assert_includes events, [ :initialize, :_ ]
    assert_includes events, :load_tasks
    assert_includes events, :load_generators
  ensure
    FileUtils.rm_rf(root) if root
    $command_actions_required = nil
  end

  test "engine actions require engine path and delegate tasks and generators to engine" do
    events = []
    root = Pathname.new(Dir.mktmpdir("command-actions-engine"))
    engine_path = root.join("engine.rb")
    engine_path.write("$command_actions_required ||= []; $command_actions_required << :engine\n")
    set_constant(:ENGINE_ROOT, root.to_s)
    set_constant(:ENGINE_PATH, engine_path.to_s)
    set_actions_constant(:ENGINE_ROOT, root.to_s)
    set_actions_constant(:ENGINE_PATH, engine_path.to_s)
    load_actions_file

    rake_application = Object.new
    rake_application.define_singleton_method(:init) { |name| events << [ :rake_init, name ] }
    rake_application.define_singleton_method(:load_rakefile) { events << :load_rakefile }
    engine = Object.new
    engine.define_singleton_method(:railtie_namespace) { :engine_namespace }
    engine.define_singleton_method(:load_generators) { events << :engine_load_generators }

    with_rake_application(rake_application) do
      with_engine_find(engine) do
        with_generators_namespace(events) do
          actions = action_object
          actions.require_application!
          actions.load_tasks
          actions.load_generators
        end
      end
    end

    assert_includes $command_actions_required, :engine
    assert_includes events, [ :rake_init, "rails" ]
    assert_includes events, :load_rakefile
    assert_includes events, [ :generators_namespace, :engine_namespace ]
    assert_includes events, :engine_load_generators
  ensure
    FileUtils.rm_rf(root) if root
    $command_actions_required = nil
  end

  private
    def action_object
      Class.new do
        include Rails::Command::Actions
      end.new
    end

    def actions_file
      File.expand_path("../../lib/rails/command/actions.rb", __dir__)
    end

    def load_actions_file
      load actions_file
    end

    def set_constant(name, value)
      remove_constant(name)
      Object.const_set(name, value)
      @temporary_constants << name unless @temporary_constants.include?(name)
    end

    def set_actions_constant(name, value)
      Rails::Command::Actions.send(:remove_const, name) if Rails::Command::Actions.const_defined?(name, false)
      Rails::Command::Actions.const_set(name, value)
    end

    def remove_constant(name)
      Object.send(:remove_const, name) if Object.const_defined?(name)
      Rails::Command::Actions.send(:remove_const, name) if defined?(Rails::Command::Actions) && Rails::Command::Actions.const_defined?(name, false)
    end

    def with_rails_application(application)
      singleton = class << Rails; self; end
      original = Rails.method(:application) if Rails.respond_to?(:application)
      singleton.define_method(:application) { application }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if original
    end

    def with_rake_application(application)
      require "rake"
      singleton = class << Rake; self; end
      original = Rake.method(:application)
      singleton.define_method(:application) { application }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_engine_find(engine)
      require "rails/engine"
      singleton = class << Rails::Engine; self; end
      original = Rails::Engine.method(:find)
      singleton.define_method(:find) { |root| engine if root == ENGINE_ROOT }
      yield
    ensure
      singleton.send(:remove_method, :find) if singleton.method_defined?(:find)
      singleton.define_method(:find) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_generators_namespace(events)
      require "rails/generators"
      singleton = class << Rails::Generators; self; end
      original = Rails::Generators.method(:namespace=) if Rails::Generators.respond_to?(:namespace=)
      singleton.define_method(:namespace=) { |namespace| events << [ :generators_namespace, namespace ] }
      yield
    ensure
      singleton.send(:remove_method, :namespace=) if singleton.method_defined?(:namespace=)
      singleton.define_method(:namespace=) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if original
    end
end
