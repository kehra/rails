# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/railtie"
require "active_support/cache"
require "active_support/current_attributes"
require "active_support/digest"
require "active_support/encrypted_file"
require "active_support/event_reporter"
require "active_support/isolated_execution_state"
require "active_support/key_generator"
require "active_support/message_encryptor"
require "active_support/messages/codec"
require "active_support/messages/metadata"
require "stringio"

Rails.define_singleton_method(:application) do
  @__active_support_railtie_test_application ||= Object.new.tap do |app|
    config = ActiveSupport::OrderedOptions.new
    config.filter_parameters = []
    executor = Object.new
    executor.define_singleton_method(:perform) { |&block| block.call }
    app.define_singleton_method(:config) { config }
    app.define_singleton_method(:executor) { executor }
  end
end unless Rails.respond_to?(:application)
Rails.define_singleton_method(:configuration) { ActiveSupport::OrderedOptions.new } unless Rails.respond_to?(:configuration)

class ActiveSupportRailtieTest < ActiveSupport::TestCase
  class Hooks
    attr_reader :before_class_unload_hooks, :to_run_hooks, :to_complete_hooks

    def initialize
      @before_class_unload_hooks = []
      @to_run_hooks = []
      @to_complete_hooks = []
    end

    def before_class_unload(&block) = @before_class_unload_hooks << block
    def to_run(&block) = @to_run_hooks << block
    def to_complete(&block) = @to_complete_hooks << block
    def perform(&block) = block.call
  end

  class Deprecators
    attr_accessor :silenced, :behavior, :disallowed_behavior, :disallowed_warnings

    def initialize
      @entries = {}
    end

    def []=(key, value)
      @entries[key] = value
    end

    def [](key)
      @entries[key]
    end
  end

  setup do
    @old_after_initialize = ActiveSupport::Railtie.config.after_initialize.dup
    @old_eager_load_namespaces = ActiveSupport::Railtie.config.eager_load_namespaces.dup
    @old_isolation_level = ActiveSupport::IsolatedExecutionState.isolation_level
    @old_raise_on_invalid_cache_expiration_time = ActiveSupport::Cache::Store.raise_on_invalid_cache_expiration_time
    @old_authenticated_message_encryption = ActiveSupport::MessageEncryptor.use_authenticated_message_encryption
    @old_event_context_store = ActiveSupport::EventReporter.context_store
    @old_filter_parameters = ActiveSupport.filter_parameters.dup
    @old_hash_digest_class = ActiveSupport::Digest.hash_digest_class
    @old_key_generator_hash_digest_class = ActiveSupport::KeyGenerator.hash_digest_class
    @old_default_serializer = ActiveSupport::Messages::Codec.default_serializer
    @old_use_message_serializer_for_metadata = ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata
    @old_zone_default = Time.zone_default if Time.respond_to?(:zone_default)
    @old_beginning_of_week_default = Date.beginning_of_week_default if Date.respond_to?(:beginning_of_week_default)
  end

  teardown do
    ActiveSupport::Railtie.config.after_initialize.replace(@old_after_initialize)
    ActiveSupport::Railtie.config.eager_load_namespaces.replace(@old_eager_load_namespaces)
    ActiveSupport::IsolatedExecutionState.isolation_level = @old_isolation_level
    ActiveSupport::Cache::Store.raise_on_invalid_cache_expiration_time = @old_raise_on_invalid_cache_expiration_time
    ActiveSupport::MessageEncryptor.use_authenticated_message_encryption = @old_authenticated_message_encryption
    ActiveSupport::EventReporter.context_store = @old_event_context_store
    ActiveSupport.filter_parameters = @old_filter_parameters
    ActiveSupport::Digest.hash_digest_class = @old_hash_digest_class
    ActiveSupport::KeyGenerator.hash_digest_class = @old_key_generator_hash_digest_class
    ActiveSupport::Messages::Codec.default_serializer = @old_default_serializer
    ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata = @old_use_message_serializer_for_metadata
    Time.zone_default = @old_zone_default if defined?(@old_zone_default)
    Date.beginning_of_week_default = @old_beginning_of_week_default if defined?(@old_beginning_of_week_default)
  end

  test "deprecator initializer registers Active Support deprecator" do
    app = fake_app

    run_initializer("active_support.deprecator", app)

    assert_same ActiveSupport.deprecator, app.deprecators[:active_support]
  end

  test "after initialize configuration initializers apply truthy and nil branches" do
    context_store = Class.new(ActiveSupport::EventContext)
    app = fake_app
    app.config.active_support.isolation_level = :fiber
    app.config.active_support.raise_on_invalid_cache_expiration_time = true
    app.config.active_support.use_authenticated_message_encryption = false
    app.config.active_support.event_reporter_context_store = context_store
    app.config.active_support.hash_digest_class = OpenSSL::Digest::SHA256
    app.config.active_support.key_generator_hash_digest_class = OpenSSL::Digest::SHA256
    app.config.active_support.message_serializer = :json
    app.config.active_support.use_message_serializer_for_metadata = true
    app.config.filter_parameters = [:password]

    run_initializer_and_after_initialize("active_support.isolation_level", app)
    run_initializer_and_after_initialize("active_support.raise_on_invalid_cache_expiration_time", app)
    run_initializer_and_after_initialize("active_support.set_authenticated_message_encryption", app)
    run_initializer_and_after_initialize("active_support.set_event_reporter_context_store", app)
    run_initializer_and_after_initialize("active_support.set_filter_parameters", app)
    run_initializer_and_after_initialize("active_support.set_hash_digest_class", app)
    run_initializer_and_after_initialize("active_support.set_key_generator_hash_digest_class", app)
    run_initializer_and_after_initialize("active_support.set_default_message_serializer", app)
    run_initializer_and_after_initialize("active_support.set_use_message_serializer_for_metadata", app)

    assert_equal :fiber, ActiveSupport::IsolatedExecutionState.isolation_level
    assert_equal true, ActiveSupport::Cache::Store.raise_on_invalid_cache_expiration_time
    assert_equal false, ActiveSupport::MessageEncryptor.use_authenticated_message_encryption
    assert_same context_store, ActiveSupport::EventReporter.context_store
    assert_includes ActiveSupport.filter_parameters, :password
    assert_equal OpenSSL::Digest::SHA256, ActiveSupport::Digest.hash_digest_class
    assert_equal OpenSSL::Digest::SHA256, ActiveSupport::KeyGenerator.hash_digest_class
    assert_equal :json, ActiveSupport::Messages::Codec.default_serializer
    assert_equal true, ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata

    nil_app = fake_app
    nil_app.config.active_support.use_authenticated_message_encryption = nil
    run_initializer_and_after_initialize("active_support.isolation_level", nil_app)
    run_initializer_and_after_initialize("active_support.raise_on_invalid_cache_expiration_time", nil_app)
    run_initializer_and_after_initialize("active_support.set_authenticated_message_encryption", nil_app)
    run_initializer_and_after_initialize("active_support.set_event_reporter_context_store", nil_app)
    run_initializer_and_after_initialize("active_support.set_hash_digest_class", nil_app)
    run_initializer_and_after_initialize("active_support.set_key_generator_hash_digest_class", nil_app)
    run_initializer_and_after_initialize("active_support.set_default_message_serializer", nil_app)
  end

  test "reset execution context installs executor and test helpers" do
    app = fake_app
    app.config.active_support.executor_around_test_case = true

    run_initializer("active_support.reset_execution_context", app)

    assert_equal 1, app.reloader.before_class_unload_hooks.size
    assert_equal 1, app.executor.to_run_hooks.size
    assert_equal 1, app.executor.to_complete_hooks.size
    assert_nothing_raised { app.reloader.before_class_unload_hooks.first.call }
    assert_nothing_raised { app.executor.to_run_hooks.first.call }
    assert_nothing_raised { app.executor.to_complete_hooks.first.call }

    hook = ActiveSupport.instance_variable_get(:@load_hooks)[:active_support_test_case].last.first
    test_case = Class.new
    test_case.class_eval(&hook)
    assert_includes test_case.ancestors, ActiveSupport::Executor::TestHelper

    app.config.active_support.executor_around_test_case = false
    run_initializer("active_support.reset_execution_context", app)
    hook = ActiveSupport.instance_variable_get(:@load_hooks)[:active_support_test_case].last.first
    other_test_case = Class.new
    other_test_case.class_eval(&hook)
    assert_includes other_test_case.ancestors, ActiveSupport::CurrentAttributes::TestHelper
    assert_includes other_test_case.ancestors, ActiveSupport::ExecutionContext::TestHelper
  end

  test "deprecation behavior initializer covers silencing and explicit settings" do
    app = fake_app
    app.config.active_support.report_deprecations = false

    run_initializer("active_support.deprecation_behavior", app)

    assert_equal true, app.deprecators.silenced
    assert_equal :silence, app.deprecators.behavior
    assert_equal :silence, app.deprecators.disallowed_behavior

    app = fake_app
    app.config.active_support.deprecation = :stderr
    app.config.active_support.disallowed_deprecation = :raise
    app.config.active_support.disallowed_deprecation_warnings = [/old/]

    run_initializer("active_support.deprecation_behavior", app)

    assert_equal :stderr, app.deprecators.behavior
    assert_equal :raise, app.deprecators.disallowed_behavior
    assert_equal [/old/], app.deprecators.disallowed_warnings

    run_initializer("active_support.deprecation_behavior", fake_app)
  end

  test "time zone and beginning of week initializers apply settings" do
    app = fake_app
    app.config.time_zone = "UTC"
    app.config.beginning_of_week = :monday

    run_initializer("active_support.initialize_time_zone", app)
    run_initializer("active_support.initialize_beginning_of_week", app)

    assert_equal "UTC", Time.zone_default.name
    assert_equal :monday, Date.beginning_of_week_default
    assert_includes ActiveSupport::Railtie.config.eager_load_namespaces, TZInfo
  end

  test "time zone initializer rewrites missing tzinfo data error" do
    TZInfo::DataSource.singleton_class.alias_method :active_support_railtie_test_get, :get
    TZInfo::DataSource.define_singleton_method(:get) { raise TZInfo::DataSourceNotFound, "missing" }

    error = assert_raises(TZInfo::DataSourceNotFound) do
      run_initializer("active_support.initialize_time_zone", fake_app)
    end
    assert_match(/tzinfo-data is not present/, error.message)
  ensure
    if TZInfo::DataSource.singleton_class.method_defined?(:active_support_railtie_test_get)
      TZInfo::DataSource.singleton_class.alias_method :get, :active_support_railtie_test_get
      TZInfo::DataSource.singleton_class.remove_method :active_support_railtie_test_get
    end
  end

  test "require master key initializer handles disabled and missing key" do
    run_initializer("active_support.require_master_key", fake_app)

    app = fake_app
    app.config.require_master_key = true
    app.credentials.define_singleton_method(:key) { raise ActiveSupport::EncryptedFile::MissingKeyError.new(key_path: "config/master.key", env_key: "RAILS_MASTER_KEY") }
    stderr = StringIO.new
    old_stderr = $stderr
    $stderr = stderr

    assert_raises(SystemExit) { run_initializer("active_support.require_master_key", app) }
    assert_match(/Missing encryption key/, stderr.string)
  ensure
    $stderr = old_stderr if old_stderr
  end

  test "set configs applies public active support setters" do
    original = ActiveSupport.cache_format_version
    app = fake_app
    app.config.active_support.cache_format_version = 7.1
    app.config.active_support.not_a_real_config = true

    run_initializer("active_support.set_configs", app)

    assert_equal 7.1, ActiveSupport.cache_format_version
  ensure
    ActiveSupport.cache_format_version = original if defined?(original)
  end

  private
    def run_initializer(name, app)
      initializer = ActiveSupport::Railtie.initializers.find { |candidate| candidate.name == name }
      ActiveSupport::Railtie.instance_exec(app, &initializer.instance_variable_get(:@block))
    end

    def run_initializer_and_after_initialize(name, app)
      before_count = ActiveSupport::Railtie.config.after_initialize.length
      run_initializer(name, app)
      ActiveSupport::Railtie.config.after_initialize[before_count..].each { |hook, _options| hook.call(app) if hook }
    end

    def fake_app
      config = ActiveSupport::OrderedOptions.new
      config.active_support = ActiveSupport::OrderedOptions.new
      config.filter_parameters = []
      config.time_zone = "UTC"
      config.beginning_of_week = :monday

      app = Object.new
      app.define_singleton_method(:config) { config }
      app.define_singleton_method(:deprecators) { @deprecators ||= Deprecators.new }
      app.define_singleton_method(:reloader) { @reloader ||= Hooks.new }
      app.define_singleton_method(:executor) { @executor ||= Hooks.new }
      app.define_singleton_method(:credentials) { @credentials ||= Object.new }
      Rails.instance_variable_set(:@__active_support_railtie_test_application, app)
      app
    end
end
