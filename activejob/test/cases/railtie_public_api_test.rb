# frozen_string_literal: true

require "helper"
require "active_job/railtie"
require "active_job/serializers/action_controller_parameters_serializer"

class RailtiePublicApiTest < ActiveSupport::TestCase
  FakeConfig = Struct.new(:active_job, :active_record) do
    def after_initialize(&block)
      after_initialize_blocks << block
    end

    def after_initialize_blocks
      @after_initialize_blocks ||= []
    end
  end

  FakeConfigWithoutActiveRecord = Struct.new(:active_job) do
    def after_initialize(&block)
      after_initialize_blocks << block
    end

    def after_initialize_blocks
      @after_initialize_blocks ||= []
    end
  end

  FakeApp = Struct.new(:config, :deprecators, :reloader)

  class FakeReloader
    attr_reader :wrapped

    def wrap
      @wrapped = true
      yield
    end
  end

  class FakeIntegrationTest
  end

  def setup
    super
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    @old_logger = ActiveJob::Base.logger
    @old_verbose_enqueue_logs = ActiveJob.verbose_enqueue_logs
    @old_backtrace_cleaner = ActiveJob::LogSubscriber.backtrace_cleaner
  end

  def teardown
    ActiveJob::Base.queue_adapter = @old_queue_adapter
    ActiveJob::Base.logger = @old_logger
    ActiveJob.verbose_enqueue_logs = @old_verbose_enqueue_logs
    ActiveJob::LogSubscriber.backtrace_cleaner = @old_backtrace_cleaner
    ActiveSupport.run_load_hooks(:action_dispatch_integration_test, Class.new)
    super
  end

  test "railtie exposes active job configuration defaults" do
    assert_kind_of ActiveSupport::OrderedOptions, ActiveJob::Railtie.config.active_job
    assert_equal [], ActiveJob::Railtie.config.active_job.custom_serializers
    assert_equal true, ActiveJob::Railtie.config.active_job.log_query_tags_around_perform
  end

  test "deprecator initializer registers active job deprecator" do
    app = fake_app

    run_initializer("active_job.deprecator", app)

    assert_same ActiveJob.deprecator, app.deprecators[:active_job]
  end

  test "logger and backtrace cleaner initializers apply rails logger state" do
    logger = Logger.new(nil)
    cleaner = ActiveSupport::BacktraceCleaner.new
    old_logger_method = Rails.method(:logger)
    old_backtrace_cleaner_method = Rails.method(:backtrace_cleaner)

    old_verbose = $VERBOSE
    $VERBOSE = nil
    Rails.define_singleton_method(:logger) { logger }
    Rails.define_singleton_method(:backtrace_cleaner) { cleaner }
    $VERBOSE = old_verbose

    run_initializer("active_job.logger", fake_app)
    run_initializer("active_job.backtrace_cleaner", fake_app)

    assert_same logger, ActiveJob::Base.logger
    assert_same cleaner, ActiveJob::LogSubscriber.backtrace_cleaner
  ensure
    $VERBOSE = nil
    Rails.define_singleton_method(:logger, old_logger_method) if old_logger_method
    Rails.define_singleton_method(:backtrace_cleaner, old_backtrace_cleaner_method) if old_backtrace_cleaner_method
    $VERBOSE = old_verbose
  end

  test "custom serializer and action controller parameter initializers add serializers" do
    original_serializers = ActiveJob::Serializers.serializers.dup
    custom_serializer = self.class.const_set(:CustomRailtieSerializer, Class.new(ActiveJob::Serializers::ObjectSerializer) do
      def klass
        Object
      end
    end)
    options = active_job_options(custom_serializers: [custom_serializer])

    run_initializer("active_job.custom_serializers", fake_app(active_job: options))
    run_initializer("active_job.action_controller_parameters", fake_app)
    ActiveSupport.run_load_hooks(:active_job_arguments, Object.new)
    ActiveSupport.run_load_hooks(:action_controller, Object.new)

    assert_includes ActiveJob::Serializers.serializers, custom_serializer.instance
    assert_includes ActiveJob::Serializers.serializers, ActiveJob::Serializers::ActionControllerParametersSerializer.instance
  ensure
    ActiveJob::Serializers.serializers = original_serializers if original_serializers
    self.class.send(:remove_const, :CustomRailtieSerializer) if self.class.const_defined?(:CustomRailtieSerializer, false)
  end

  test "enqueue after transaction commit initializer includes module and applies config when present" do
    original = ActiveJob::Base.enqueue_after_transaction_commit
    options = active_job_options(enqueue_after_transaction_commit: false)

    run_initializer("active_job.enqueue_after_transaction_commit", fake_app(active_job: options))

    assert_includes ActiveJob::Base.ancestors, ActiveJob::EnqueueAfterTransactionCommit
    assert_equal false, ActiveJob::Base.enqueue_after_transaction_commit
  ensure
    ActiveJob::Base.enqueue_after_transaction_commit = original if ActiveJob::Base.respond_to?(:enqueue_after_transaction_commit=)
  end

  test "enqueue after transaction commit initializer leaves default when config key is absent" do
    original = ActiveJob::Base.enqueue_after_transaction_commit

    run_initializer("active_job.enqueue_after_transaction_commit", fake_app)

    assert_equal original, ActiveJob::Base.enqueue_after_transaction_commit
  end

  test "set configs initializer applies global active job and base configs" do
    options = active_job_options(
      verbose_enqueue_logs: true,
      queue_adapter: :inline,
      custom_serializers: [:ignored],
      log_query_tags_around_perform: false,
      enqueue_after_transaction_commit: false,
      unknown_config: :ignored
    )
    config = FakeConfig.new(options, nil)
    app = FakeApp.new(config, {}, FakeReloader.new)
    after_initialize_blocks = []
    railtie_config = ActiveJob::Railtie.config
    old_after_initialize = railtie_config.method(:after_initialize)
    old_verbose = $VERBOSE
    $VERBOSE = nil
    railtie_config.define_singleton_method(:after_initialize) { |&block| after_initialize_blocks << block }
    $VERBOSE = old_verbose

    run_initializer("active_job.set_configs", app)
    after_initialize_blocks.each(&:call)
    ActiveSupport.run_load_hooks(:action_dispatch_integration_test, FakeIntegrationTest)

    assert_equal true, ActiveJob.verbose_enqueue_logs
    assert_instance_of ActiveJob::QueueAdapters::InlineAdapter, ActiveJob::Base.queue_adapter
    assert_includes FakeIntegrationTest.ancestors, ActiveJob::TestHelper
  ensure
    $VERBOSE = nil
    railtie_config.define_singleton_method(:after_initialize, old_after_initialize) if railtie_config && old_after_initialize
    $VERBOSE = old_verbose
  end

  test "reloader hook wraps active job callback execution" do
    reloader = FakeReloader.new

    run_initializer("active_job.set_reloader_hook", fake_app(reloader: reloader))

    callback_ran = false
    ActiveJob::Callbacks.run_callbacks(:execute) { callback_ran = true }

    assert_equal true, callback_ran
    assert_equal true, reloader.wrapped
  end

  test "query log tags initializer configures active record when enabled" do
    app = fake_app(active_record: ActiveSupport::OrderedOptions.new)
    app.config.active_record.query_log_tags_enabled = true
    app.config.active_record.query_log_tags = []
    app.config.active_job.log_query_tags_around_perform = true

    with_fake_active_record_query_logs do
      run_initializer("active_job.query_log_tags", app)
      ActiveSupport.run_load_hooks(:active_record, Object.new)
      assert_equal "String", ::ActiveRecord::QueryLogs.taggings[:job].call(job: "payload")
      assert_nil ::ActiveRecord::QueryLogs.taggings[:job].call({})
    end

    assert_equal [:job], app.config.active_record.query_log_tags
  end

  test "query log tags initializer noops when active record config is absent or disabled" do
    app_without_active_record = FakeApp.new(FakeConfigWithoutActiveRecord.new(active_job_options), {}, FakeReloader.new)
    run_initializer("active_job.query_log_tags", app_without_active_record)

    app = fake_app(active_record: ActiveSupport::OrderedOptions.new)
    app.config.active_record.query_log_tags_enabled = false
    app.config.active_record.query_log_tags = []
    app.config.active_job.log_query_tags_around_perform = true

    run_initializer("active_job.query_log_tags", app)

    assert_equal [], app.config.active_record.query_log_tags
  end

  private
    def run_initializer(name, app)
      ActiveJob::Railtie.initializers.find { |initializer| initializer.name == name }.bind(ActiveJob::Railtie).run(app)
    end

    def fake_app(active_job: active_job_options, active_record: nil, reloader: FakeReloader.new)
      FakeApp.new(FakeConfig.new(active_job, active_record), {}, reloader)
    end

    def active_job_options(values = {})
      ActiveSupport::OrderedOptions.new.tap do |options|
        values.each { |key, value| options[key] = value }
      end
    end

    def with_fake_active_record_query_logs
      old_active_record = Object.const_get(:ActiveRecord) if Object.const_defined?(:ActiveRecord)
      Object.send(:remove_const, :ActiveRecord) if Object.const_defined?(:ActiveRecord)
      active_record = Module.new
      query_logs = Module.new
      query_logs.singleton_class.attr_accessor :taggings
      query_logs.taggings = {}
      active_record.const_set(:QueryLogs, query_logs)
      Object.const_set(:ActiveRecord, active_record)
      yield
    ensure
      Object.send(:remove_const, :ActiveRecord) if Object.const_defined?(:ActiveRecord)
      Object.const_set(:ActiveRecord, old_active_record) if defined?(old_active_record) && old_active_record
    end
end
