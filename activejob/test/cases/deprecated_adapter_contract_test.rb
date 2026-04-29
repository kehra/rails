# frozen_string_literal: true

require "helper"
require "fileutils"
require "tmpdir"

class DeprecatedAdapterContractTest < ActiveSupport::TestCase
  def with_builtin_adapter(adapter_name, file_name, stub_require: nil, stub_content: "# frozen_string_literal: true\n")
    adapters = ActiveJob::QueueAdapters
    had_previous = adapters.const_defined?(adapter_name, false)
    previous_autoload = adapters.autoload?(adapter_name)
    previous = adapters.const_get(adapter_name, false) if had_previous && !previous_autoload
    stub_path = nil

    if stub_require
      stub_path = Dir.mktmpdir("active_job_adapter_stub")
      File.write(File.join(stub_path, "#{stub_require}.rb"), stub_content)
      $LOAD_PATH.unshift(stub_path)
    end

    adapters.send(:remove_const, adapter_name) if had_previous
    load File.expand_path("../../lib/active_job/queue_adapters/#{file_name}_adapter.rb", __dir__)
    yield adapters.const_get(adapter_name, false)
  ensure
    adapters.send(:remove_const, adapter_name) if adapters.const_defined?(adapter_name, false)
    if previous_autoload
      adapters.autoload(adapter_name, previous_autoload)
    elsif had_previous
      adapters.const_set(adapter_name, previous)
    end
    $LOAD_PATH.delete(stub_path) if stub_path
    FileUtils.remove_entry(stub_path) if stub_path && File.directory?(stub_path)
  end

  test "built-in backburner adapter check_adapter warns about deprecation" do
    with_builtin_adapter(:BackburnerAdapter, "backburner", stub_require: "backburner") do |adapter_class|
      message = <<~MSG.squish
        The built-in `backburner` adapter is deprecated and will be removed in Rails 9.0.
        Please upgrade `backburner` gem to version 1.7 or later to use the `backburner` gem's adapter.
      MSG

      assert_deprecated(message, ActiveJob.deprecator) do
        adapter_class.new.check_adapter
      end
    end
  end

  test "built-in delayed_job adapter check_adapter warns about deprecation" do
    with_builtin_adapter(:DelayedJobAdapter, "delayed_job", stub_require: "delayed_job") do |adapter_class|
      message = <<~MSG.squish
        The built-in `delayed_job` adapter is deprecated and will be removed in Rails 9.0.
        Please upgrade `delayed_job` gem to version 4.2.0 or later to use the `delayed_job` gem's adapter.
      MSG

      assert_deprecated(message, ActiveJob.deprecator) do
        adapter_class.new.check_adapter
      end
    end
  end

  test "built-in queue_classic adapter check_adapter warns and builds QC queue" do
    stub = <<~RUBY
      # frozen_string_literal: true
      module QC
        class Queue
          attr_reader :name

          def initialize(name)
            @name = name
          end
        end
      end
    RUBY

    with_builtin_adapter(:QueueClassicAdapter, "queue_classic", stub_require: "queue_classic", stub_content: stub) do |adapter_class|
      message = <<~MSG.squish
        The built-in `queue_classic` adapter is deprecated and will be removed in Rails 9.0.
      MSG

      adapter = adapter_class.new
      assert_deprecated(message, ActiveJob.deprecator) do
        adapter.check_adapter
      end

      queue = adapter.build_queue("critical")
      assert_instance_of QC::Queue, queue
      assert_equal "critical", queue.name
    end
  ensure
    Object.send(:remove_const, :QC) if Object.const_defined?(:QC, false)
  end

  test "built-in resque adapter check_adapter warns about deprecation" do
    with_builtin_adapter(:ResqueAdapter, "resque", stub_require: "resque", stub_content: "# frozen_string_literal: true\nmodule Resque; end\n") do |adapter_class|
      message = <<~MSG.squish
        The built-in `resque` adapter is deprecated and will be removed in Rails 9.0.
        Please upgrade `resque` gem to version 3.0 or later to use the `resque` gem's adapter.
      MSG

      assert_deprecated(message, ActiveJob.deprecator) do
        adapter_class.new.check_adapter
      end
    end
  ensure
    Object.send(:remove_const, :Resque) if Object.const_defined?(:Resque, false)
  end

  test "built-in sneakers adapter initializes monitor and warns about deprecation" do
    stub = <<~RUBY
      # frozen_string_literal: true
      module Sneakers
        module Worker
          def self.included(base)
            base.extend(ClassMethods)
          end

          module ClassMethods
            def from_queue(*)
            end

            def enqueue(*)
            end
          end
        end
      end
    RUBY

    with_builtin_adapter(:SneakersAdapter, "sneakers", stub_require: "sneakers", stub_content: stub) do |adapter_class|
      message = <<~MSG.squish
        The built-in `sneakers` adapter is deprecated and will be removed in Rails 9.0.
        Please migrate from `sneakers` gem to `kicks` gem version 3.1.1 or later to use `ActiveJob` adapter from `kicks`.
      MSG

      adapter = adapter_class.new
      assert_instance_of Monitor, adapter.instance_variable_get(:@monitor)
      assert_deprecated(message, ActiveJob.deprecator) do
        adapter.check_adapter
      end
    end
  ensure
    Object.send(:remove_const, :Sneakers) if Object.const_defined?(:Sneakers, false)
  end
end
