# frozen_string_literal: true

require "helper"
require "fileutils"
require "tmpdir"

class DeprecatedAdapterContractTest < ActiveSupport::TestCase
  def with_builtin_adapter(adapter_name, file_name, stub_require: nil)
    adapters = ActiveJob::QueueAdapters
    had_previous = adapters.const_defined?(adapter_name, false)
    previous_autoload = adapters.autoload?(adapter_name)
    previous = adapters.const_get(adapter_name, false) if had_previous && !previous_autoload
    stub_path = nil

    if stub_require
      stub_path = Dir.mktmpdir("active_job_adapter_stub")
      File.write(File.join(stub_path, "#{stub_require}.rb"), "# frozen_string_literal: true\n")
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
end
