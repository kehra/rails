# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/rake/rake_command"

class RakePublicContractTest < ActiveSupport::TestCase
  test "printing commands exposes documented non app rake tasks" do
    root = Pathname.new("/tmp/app")
    app_task = fake_task("app:task", "App task", ["/tmp/app/lib/tasks/app.rake"])
    framework_task = fake_task("rails:task", "Framework task", ["/rails/railties/lib/tasks/framework.rake"])
    undocumented_task = fake_task("hidden:task", nil, ["/rails/railties/lib/tasks/hidden.rake"])
    rake = fake_rake(tasks: [app_task, framework_task, undocumented_task])

    with_singleton_method(Rails::Command, :root, -> { root }) do
      with_rake_application(rake) do
        Rails::Command::RakeCommand.remove_instance_variable(:@rake_tasks) if Rails::Command::RakeCommand.instance_variable_defined?(:@rake_tasks)
        assert_equal [["rails:task", "Framework task"]], Rails::Command::RakeCommand.printing_commands
      end
    end
  end

  test "perform initializes rake reports errors and runs top level tasks" do
    rake = fake_rake(top_level_tasks: ["default", "known"], lookup: { "known" => Object.new })

    with_singleton_method(Rails::Command, :root, -> { Pathname.new("/tmp/app") }) do
      with_rake_application(rake) do
        Rails::Command::RakeCommand.perform("known", ["--trace"], {})
      end
    end

    assert_equal [["bin/rails", ["known", "--trace"]]], rake.inits
    assert_equal 1, rake.load_rakefile_count
    assert_equal 1, rake.exception_handling_count
    assert_equal 1, rake.top_level_count
    assert_equal "\\A(?!/tmp/app)", rake.options.suppress_backtrace_pattern.source
  end

  test "perform raises unrecognized command and caches rake tasks" do
    rake = fake_rake(top_level_tasks: ["missing[1]"], lookup: {})
    rake.tasks = [fake_task("available", "Available", ["/rails/task.rake"])]

    error = assert_raises(Rails::Command::UnrecognizedCommandError) do
      with_rake_application(rake) do
        Rails::Command::RakeCommand.perform("missing", [], {})
      end
    end

    assert_equal "missing[1]", error.name
    assert_equal rake.tasks, Rails::Command::RakeCommand.instance_variable_get(:@rake_tasks)
  end

  private
    def fake_task(name, comment, locations)
      Struct.new(:name_with_args, :comment, :locations).new(name, comment, locations)
    end

    def fake_rake(tasks: [], top_level_tasks: [], lookup: {})
      Struct.new(:tasks, :top_level_tasks, :lookup_hash, :options, :inits, :load_rakefile_count, :exception_handling_count, :top_level_count) do
        def init(bin, args) = inits << [bin, args]
        def load_rakefile = self.load_rakefile_count += 1
        def lookup(name) = lookup_hash[name]
        def standard_exception_handling
          self.exception_handling_count += 1
          yield
        end
        def top_level = self.top_level_count += 1
      end.new(tasks, top_level_tasks, lookup, Struct.new(:suppress_backtrace_pattern).new, [], 0, 0, 0)
    end

    def with_rake_application(rake)
      require "rake"
      singleton = class << Rake; self; end
      original = Rake.method(:with_application)
      singleton.send(:remove_method, :with_application) if singleton.method_defined?(:with_application)
      singleton.define_method(:with_application) { |&block| block.call(rake) }
      yield
    ensure
      singleton.send(:remove_method, :with_application) if singleton.method_defined?(:with_application)
      singleton.define_method(:with_application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
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
end
