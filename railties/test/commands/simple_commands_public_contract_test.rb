# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/destroy/destroy_command"
require "rails/commands/dev/dev_command"
require "rails/commands/devcontainer/devcontainer_command"
require "rails/commands/gem_help/gem_help_command"
require "rails/commands/generate/generate_command"
require "rails/commands/help/help_command"
require "rails/commands/initializers/initializers_command"
require "rails/commands/middleware/middleware_command"
require "rails/commands/new/new_command"
require "rails/commands/notes/notes_command"
require "rails/commands/plugin/plugin_command"
require "rails/commands/restart/restart_command"
require "rails/commands/secret/secret_command"
require "rails/commands/stats/stats_command"
require "rails/commands/version/version_command"

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

  test "gem help command prints hidden usage" do
    command = Rails::Command::GemHelpCommand.new([], [])
    with_singleton_method(Rails::Command::GemHelpCommand, :class_usage, -> { "gem usage" }) do
      assert_equal "gem usage\n", capture(:stdout) { command.perform }
    end
  end

  test "generate help boots application loads generators and prints generator help" do
    command = Rails::Command::GenerateCommand.new([], [])
    calls = []
    command.define_singleton_method(:boot_application!) { calls << :boot_application }
    command.define_singleton_method(:load_generators) { calls << :load_generators }

    with_singleton_method(Rails::Generators, :help, ->(name) { calls << [ :help, name ] }) do
      command.help
    end

    assert_equal [ :boot_application, :load_generators, [ :help, "generate" ] ], calls
  end

  test "generate perform shows help without generator and invokes named generator with remaining args" do
    help_command = Rails::Command::GenerateCommand.new([], [])
    help_command.define_singleton_method(:help) { :helped }

    assert_equal :helped, help_command.perform

    original_argv = ARGV.dup
    command = Rails::Command::GenerateCommand.new(["model", "Post", "title:string"], [])
    calls = []
    command.define_singleton_method(:boot_application!) { calls << :boot_application }
    command.define_singleton_method(:load_generators) { calls << :load_generators }

    with_singleton_method(Rails::Command, :root, -> { Pathname.new("/tmp/app") }) do
      with_singleton_method(Rails::Generators, :invoke, ->(*args, **options) { calls << [ args, options ] }) do
        command.perform
      end
    end

    assert_equal ["Post", "title:string"], ARGV
    assert_equal :boot_application, calls[0]
    assert_equal :load_generators, calls[1]
    assert_equal [["model", ["Post", "title:string"]], { behavior: :invoke, destination_root: Pathname.new("/tmp/app") }], calls[2]
  ensure
    ARGV.replace(original_argv) if original_argv
  end

  test "help command prints usage and extended command table excluding commands already in usage" do
    command = Rails::Command::HelpCommand.new([], [])
    printed_table = nil
    command.define_singleton_method(:print_table) do |rows, options|
      printed_table = [ rows, options ]
    end

    with_singleton_method(Rails::Command::HelpCommand, :class_usage, -> { "core usage" }) do
      with_singleton_method(Rails::Command, :printing_commands, -> { [["server", "skip"], ["routes", "Routes"], ["about", "About"]] }) do
        output = capture(:stdout) { command.help_extended }
        assert_includes output, "core usage"
        assert_includes output, "In addition to those commands"
      end
    end

    assert_equal [[ ["about", "About"], ["routes", "Routes"] ], { truncate: true }], printed_table
  end

  test "initializers command boots and prints tsorted initializers" do
    initializer = Struct.new(:context_class, :name).new("Demo::Application", "load_config")
    initializers = Object.new
    initializers.define_singleton_method(:tsort_each) { |&block| block.call(initializer) }
    app = Object.new
    app.define_singleton_method(:initializers) { initializers }
    command = Rails::Command::InitializersCommand.new([], [])
    booted = false
    command.define_singleton_method(:boot_application!) { booted = true }

    output = with_rails_application(app) { capture(:stdout) { command.perform } }

    assert booted
    assert_equal "Demo::Application.load_config\n", output
  end

  test "middleware command boots and prints middleware stack and app routes" do
    middleware = [ Struct.new(:inspect).new("MiddlewareOne"), Struct.new(:inspect).new("MiddlewareTwo") ]
    config = Object.new
    config.define_singleton_method(:middleware) { middleware }
    app_class = Class.new
    app_class.singleton_class.define_method(:name) { "Demo::Application" }
    app = app_class.new
    command = Rails::Command::MiddlewareCommand.new([], [])
    booted = false
    command.define_singleton_method(:boot_application!) { booted = true }

    output = with_rails_application(app) do
      with_singleton_method(Rails, :configuration, -> { config }) do
        capture(:stdout) { command.perform }
      end
    end

    assert booted
    assert_includes output, "use MiddlewareOne"
    assert_includes output, "use MiddlewareTwo"
    assert_includes output, "run Demo::Application.routes"
  end

  test "new command help delegates to application help and perform exits inside existing app" do
    invoked = []
    with_singleton_method(Rails::Command, :invoke, ->(name, args) { invoked << [name, args] }) do
      Rails::Command::NewCommand.new([], []).help
    end

    assert_equal [[:application, ["--help"]]], invoked

    output = capture(:stdout) do
      error = assert_raises(SystemExit) { Rails::Command::NewCommand.new([], []).perform }
      assert_equal 1, error.status
    end
    assert_includes output, "Can't initialize a new Rails application within the directory of another"
    assert_includes output, "Type 'rails' for help."
  end

  test "notes command boots and enumerates default and explicit annotation tags" do
    calls = []
    command = Rails::Command::NotesCommand.new([], [])
    command.define_singleton_method(:boot_application!) { calls << :boot_application }

    annotation = Rails::SourceAnnotationExtractor::Annotation
    with_singleton_method(annotation, :tags, -> { ["FIXME", "TODO"] }) do
      with_singleton_method(annotation, :directories, -> { ["app", "test"] }) do
        with_singleton_method(Rails::SourceAnnotationExtractor, :enumerate, ->(pattern, **options) { calls << [pattern, options] }) do
          command.perform
        end
      end
    end

    assert_equal [ :boot_application, ["FIXME|TODO", { tag: true, dirs: ["app", "test"] }] ], calls

    calls.clear
    command = Rails::Command::NotesCommand.new([], ["--annotations=OPTIMIZE"])
    command.define_singleton_method(:boot_application!) { calls << :boot_application }
    with_singleton_method(Rails::SourceAnnotationExtractor, :enumerate, ->(pattern, **options) { calls << [pattern, options] }) do
      command.perform
    end

    assert_equal [ :boot_application, ["OPTIMIZE", { tag: false, dirs: Rails::SourceAnnotationExtractor::Annotation.directories }] ], calls
  end

  test "plugin command banner help rc merging and generator delegation" do
    assert_equal "rails plugin new [options]", Rails::Command::PluginCommand.banner

    command = Rails::Command::PluginCommand.new([], [])
    generator_args = []
    command.define_singleton_method(:run_plugin_generator) { |args| generator_args << args }
    command.help
    assert_equal [["--help"]], generator_args

    railsrc = Tempfile.new("railsrc")
    railsrc.write("--skip-action-mailer\n--skip-active-job --dummy-path spec/dummy\n")
    railsrc.close

    command = Rails::Command::PluginCommand.new([], ["--rc=#{railsrc.path}"])
    generator_args.clear
    command.define_singleton_method(:run_plugin_generator) { |args| generator_args << args }
    output = capture(:stdout) { command.perform("new", "demo") }

    assert_includes output, "Using --skip-action-mailer --skip-active-job --dummy-path spec/dummy from #{railsrc.path}"
    assert_equal [["demo", "--skip-action-mailer", "--skip-active-job", "--dummy-path", "spec/dummy"]], generator_args

    command = Rails::Command::PluginCommand.new([], ["--no-rc"])
    generator_args.clear
    command.define_singleton_method(:run_plugin_generator) { |args| generator_args << args }
    command.perform("help", "demo")
    assert_equal [["demo", "--help"]], generator_args

    missing_rc = File.join(Dir.tmpdir, "missing-railsrc-#{$$}")
    command = Rails::Command::PluginCommand.new([], ["--rc=#{missing_rc}"])
    generator_args.clear
    command.define_singleton_method(:run_plugin_generator) { |args| generator_args << args }
    command.perform("new", "empty")
    assert_equal [["empty"]], generator_args
  ensure
    railsrc&.unlink
  end

  test "plugin private runner starts plugin generator" do
    require "rails/generators/rails/plugin/plugin_generator"
    calls = []
    with_singleton_method(Rails::Generators::PluginGenerator, :start, ->(args) { calls << args }) do
      command = Rails::Command::PluginCommand.new([], [])
      command.send(:run_plugin_generator, ["demo"])
    end

    assert_equal [["demo"]], calls
  end

  test "restart command creates tmp directory and touches restart file" do
    root = Pathname.new(Dir.mktmpdir)
    with_singleton_method(Rails::Command, :application_root, -> { root }) do
      Rails::Command::RestartCommand.new([], []).perform
    end

    assert File.directory?(root.join("tmp"))
    assert File.file?(root.join("tmp/restart.txt"))
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "secret command prints secure random hex" do
    with_singleton_method(SecureRandom, :hex, ->(length) { "x" * length }) do
      assert_equal "#{'x' * 64}\n", capture(:stdout) { Rails::Command::SecretCommand.new([], []).perform }
    end
  end

  test "stats command boots application filters existing directories and returns code statistics" do
    root = Pathname.new(Dir.mktmpdir)
    FileUtils.mkdir_p(root.join("app/models"))
    command = Rails::Command::StatsCommand.new([], [])
    booted = false
    command.define_singleton_method(:boot_application!) { booted = true }
    output = with_singleton_method(Rails::Command, :application_root, -> { root }) do
      capture(:stdout) { command.perform }
    end

    assert booted
    assert_includes output, "Models"
  ensure
    FileUtils.rm_rf(root) if root
  end

  test "version command delegates to application version" do
    invoked = []
    with_singleton_method(Rails::Command, :invoke, ->(name, args) { invoked << [name, args] }) do
      Rails::Command::VersionCommand.new([], []).perform
    end

    assert_equal [[:application, ["--version"]]], invoked
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

    def replace_constant_path(path, value)
      names = path.split("::")
      parent = names[0...-1].inject(Object) { |mod, name| mod.const_get(name) }
      name = names.last.to_sym
      original = parent.const_get(name) if parent.const_defined?(name, false)
      parent.send(:remove_const, name) if parent.const_defined?(name, false)
      parent.const_set(name, value)
      yield
    ensure
      parent.send(:remove_const, name) if parent&.const_defined?(name, false)
      parent.const_set(name, original) if defined?(original) && original
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
