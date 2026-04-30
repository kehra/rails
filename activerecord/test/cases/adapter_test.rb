# frozen_string_literal: true

require "cases/helper"
require "support/connection_helper"
require "models/book"
require "models/post"
require "models/author"
require "models/event"

module ActiveRecord
  class AdapterTest < ActiveRecord::TestCase
    def setup
      @connection = ActiveRecord::Base.lease_connection
      @connection.materialize_transactions
    end

    def test_type_map_is_ractor_shareable
      # This is testing internals. Please feel free to remove this test
      # or change it when internals change. The point is to make sure
      # the type map is Ractor shareable.
      @connection.tables.each do |table|
        @connection.columns(table).each do |column|
          assert_ractor_shareable @connection.send(:lookup_cast_type, column.sql_type)
        end
      end
    end

    ##
    # PostgreSQL does not support null bytes in strings
    unless current_adapter?(:PostgreSQLAdapter) ||
        (current_adapter?(:SQLite3Adapter) && !ActiveRecord::Base.lease_connection.prepared_statements)
      def test_update_prepared_statement
        b = Book.create(name: "my \x00 book")
        b.reload
        assert_equal "my \x00 book", b.name
        b.update(name: "my other \x00 book")
        b.reload
        assert_equal "my other \x00 book", b.name
      end
    end

    def test_create_record_with_pk_as_zero
      Book.create(id: 0)
      assert_equal 0, Book.find(0).id
      assert_nothing_raised { Book.destroy(0) }
    end

    def test_valid_column
      @connection.native_database_types.each_key do |type|
        assert @connection.valid_type?(type)
        assert @connection.class.valid_type?(type)
      end
    end

    def test_database_limit_public_defaults
      limits = Class.new do
        include ActiveRecord::ConnectionAdapters::DatabaseLimits
      end.new

      assert_equal 64, limits.max_identifier_length
      assert_equal limits.max_identifier_length, limits.table_name_length
      assert_equal limits.max_identifier_length, limits.table_alias_length
      assert_equal limits.max_identifier_length, limits.index_name_length
      assert_equal 65535, limits.send(:bind_params_length)

      assert_operator @connection.table_name_length, :>, 0
      assert_operator @connection.table_alias_length, :>, 0
      assert_operator @connection.index_name_length, :>, 0
      assert_operator @connection.send(:bind_params_length), :>, 0
    end

    def test_abstract_adapter_public_default_contracts
      adapter_class = Class.new(ActiveRecord::ConnectionAdapters::AbstractAdapter) do
        def self.native_database_types = { string: { name: "varchar" } }
        def columns(_table_name) = [Struct.new(:name).new("title")]
        def connect! = true
      end

      adapter_class.const_set(:ADAPTER_NAME, "TestAbstract")
      adapter = adapter_class.new({ prepared_statements: false, advisory_locks: true, default_timezone: "utc" })

      assert_equal 5, adapter_class.type_cast_config_to_integer(5)
      assert_equal 42, adapter_class.type_cast_config_to_integer("42")
      assert_equal "not_int", adapter_class.type_cast_config_to_integer("not_int")
      assert_equal false, adapter_class.type_cast_config_to_boolean("false")
      assert_equal true, adapter_class.type_cast_config_to_boolean(true)
      assert_equal :utc, adapter_class.validate_default_timezone("utc")
      assert_equal :local, adapter_class.validate_default_timezone("local")
      assert_nil adapter_class.validate_default_timezone(nil)
      assert_raises(ArgumentError) { adapter_class.validate_default_timezone("tokyo") }
      assert_raises(NotImplementedError) { adapter_class.dbconsole({}) }
      Dir.mktmpdir("abstract-adapter-client") do |dir|
        client = File.join(dir, "ar-client")
        File.write(client, "#!/bin/sh\n")
        File.chmod(0755, client)
        old_path = ENV["PATH"]
        ENV["PATH"] = dir
        executed = nil
        adapter_class.define_singleton_method(:exec) { |command, *args| executed = [command, args] }
        adapter_class.send(:find_cmd_and_exec, "ar-client", "--version")
        assert_equal [client, ["--version"]], executed
      ensure
        ENV["PATH"] = old_path
      end
      old_path = ENV["PATH"]
      ENV["PATH"] = ""
      adapter_class.define_singleton_method(:abort) { |message| raise message }
      error = assert_raises(RuntimeError) { adapter_class.send(:find_cmd_and_exec, ["missing-client"]) }
      assert_match(/Couldn't find database client: missing-client/, error.message)
      ENV["PATH"] = old_path
      extended_type_map = adapter_class.extended_type_map(default_timezone: :utc)
      assert_kind_of ActiveRecord::Type::Time, extended_type_map.lookup("time(6)")
      assert_equal :utc, adapter.default_timezone
      assert_kind_of ActiveRecord::Type::Time, adapter.send(:type_map).lookup("time(6)")

      adapter_class.migration_strategy = :custom_strategy
      assert_equal :custom_strategy, adapter_class.migration_strategy
      assert_predicate adapter_class, :migration_strategy?
      assert_equal :custom_strategy, adapter.migration_strategy
      assert_predicate adapter, :migration_strategy?

      version = ActiveRecord::ConnectionAdapters::AbstractAdapter::Version.new("12.3.4", "12.3.4-full")
      assert_equal "12.3.4", version.to_s
      assert_equal "12.3.4-full", version.full_version_string
      assert_operator version, :>, "12.3.3"

      assert_equal true, adapter.valid_type?(:string)
      assert_equal true, adapter_class.valid_type?(:string)
      assert_equal false, adapter.valid_type?(:integer)
      assert_equal false, adapter_class.valid_type?(:integer)
      assert_equal false, adapter.replica?
      assert_equal false, adapter.preventing_writes?
      assert_equal false, adapter.prepared_statements?
      assert_equal 1, adapter.connection_retries
      assert_equal 2, adapter.verify_timeout
      assert_nil adapter.retry_deadline
      assert_operator adapter.pool_jitter(10.0), :<=, 10.0
      assert_operator adapter.pool_jitter(10.0), :>=, 0.0
      assert_nil adapter.seconds_since_last_activity
      assert_nil adapter.connection_age
      assert_operator adapter.seconds_idle, :>=, 0
      adapter.allow_preconnect = true
      assert_equal true, adapter.allow_preconnect

      assert_equal "TestAbstract", adapter.adapter_name
      assert_equal false, adapter.supports_ddl_transactions?
      assert_equal false, adapter.supports_bulk_alter?
      assert_equal false, adapter.supports_savepoints?
      assert_equal false, adapter.savepoint_errors_invalidate_transactions?
      assert_equal false, adapter.supports_restart_db_transaction?
      assert_equal false, adapter.supports_advisory_locks?
      assert_equal false, adapter.prefetch_primary_key?(:posts)
      assert_equal false, adapter.supports_partitioned_indexes?
      assert_equal false, adapter.supports_index_sort_order?
      assert_equal false, adapter.supports_partial_index?
      assert_equal false, adapter.supports_index_include?
      assert_equal false, adapter.supports_expression_index?
      assert_equal false, adapter.supports_explain?
      assert_equal false, adapter.supports_transaction_isolation?
      assert_equal false, adapter.supports_extensions?
      assert_equal false, adapter.supports_indexes_in_create?
      assert_equal false, adapter.supports_foreign_keys?
      assert_equal false, adapter.supports_validate_constraints?
      assert_equal false, adapter.supports_deferrable_constraints?
      assert_equal false, adapter.supports_check_constraints?
      assert_equal false, adapter.supports_exclusion_constraints?
      assert_equal false, adapter.supports_unique_constraints?
      assert_equal false, adapter.supports_views?
      assert_equal false, adapter.supports_materialized_views?
      assert_equal false, adapter.supports_datetime_with_precision?
      assert_equal false, adapter.supports_json?
      assert_equal false, adapter.supports_comments?
      assert_equal false, adapter.supports_comments_in_create?
      assert_equal false, adapter.supports_virtual_columns?
      assert_equal false, adapter.supports_foreign_tables?
      assert_equal false, adapter.supports_optimizer_hints?
      assert_equal false, adapter.supports_common_table_expressions?
      assert_equal false, adapter.supports_lazy_transactions?
      assert_equal false, adapter.supports_insert_returning?
      assert_equal false, adapter.supports_insert_on_duplicate_skip?
      assert_equal false, adapter.supports_insert_on_duplicate_update?
      assert_equal false, adapter.supports_insert_conflict_target?
      assert_equal true, adapter.supports_concurrent_connections?
      assert_equal false, adapter.supports_nulls_not_distinct?
      assert_equal false, adapter.supports_disabling_indexes?
      assert_equal false, adapter.async_enabled?
      assert_equal false, adapter.advisory_locks_enabled?
      assert_equal [], adapter.extensions
      assert_equal({}, adapter.index_algorithms)
      assert_equal true, adapter.disable_referential_integrity { true }
      assert_nil adapter.check_all_foreign_keys_valid!
      assert_nil adapter.active?
      assert_equal false, adapter.connected?
      assert_nil adapter.discard!
      assert_equal false, adapter.requires_reloading?
      assert_equal false, adapter.verified?
      assert_kind_of ActiveRecord::Result, adapter.send(:build_result, columns: ["id"], rows: [[1]])
      assert_kind_of Arel::Visitors::ToSql, adapter.send(:arel_visitor)
      assert_nil adapter.send(:build_statement_pool)
      assert_equal true, adapter.send(:can_perform_case_insensitive_comparison_for?, nil)
      assert_equal true, adapter.send(:default_index_type?, Struct.new(:using).new(nil))
      assert_equal false, adapter.send(:default_index_type?, Struct.new(:using).new(:btree))

      attribute_class = Struct.new(:name, :relation) do
        def eq(value) = [:eq, value]
        def lower = LoweredAttribute.new(self)
      end
      lowered_attribute_class = Class.new do
        def initialize(attribute) = @attribute = attribute
        def eq(value) = [:lower_eq, @attribute.name, value]
      end
      Object.const_set(:LoweredAttribute, lowered_attribute_class) unless Object.const_defined?(:LoweredAttribute)
      relation = Struct.new(:name) { def lower(value) = [:lower, value] }.new("posts")
      attribute = attribute_class.new("title", relation)
      cache = Class.new do
        def columns_hash(table_name) = { "title" => Struct.new(:name).new("title") }
      end.new
      adapter.pool = Struct.new(:schema_cache) do
        def schema_reflection = nil
        def db_config = Struct.new(:name, :env_name).new("primary", "test")
        def role = :writing
        def shard = :default
      end.new(cache)
      assert_equal [:eq, "value"], adapter.case_sensitive_comparison(attribute, "value")
      assert_equal [:lower_eq, "title", [:lower, "value"]], adapter.case_insensitive_comparison(attribute, "value")
      adapter.define_singleton_method(:can_perform_case_insensitive_comparison_for?) { |_column| false }
      assert_equal [:eq, "value"], adapter.case_insensitive_comparison(attribute, "value")
      assert_equal "title", adapter.send(:column_for, :posts, :title).name
      assert_raises(ActiveRecord::ActiveRecordError) { adapter.send(:column_for, :posts, :missing) }
      assert_equal "title", adapter.send(:column_for_attribute, attribute).name

      assert adapter.send(:retryable_connection_error?, ActiveRecord::ConnectionNotEstablished.new)
      assert adapter.send(:retryable_connection_error?, ActiveRecord::ConnectionFailed.new)
      refute adapter.send(:retryable_connection_error?, ActiveRecord::ConnectionNotDefined.new)
      refute adapter.send(:retryable_query_error?, ActiveRecord::StatementInvalid.new("boom"))
      assert_raises(NotImplementedError) { adapter.send(:reconnect) }
      assert_equal 0, adapter.send(:backoff, 0)
      translated = adapter.send(:translate_exception_class, RuntimeError.new("boom"), "SELECT", [])
      assert_instance_of RuntimeError, translated
      statement_error = adapter.send(:translate_exception_class, StandardError.new("boom"), "SELECT", [])
      assert_instance_of ActiveRecord::StatementInvalid, statement_error
      active_record_error = ActiveRecord::ActiveRecordError.new("boom")
      assert_same active_record_error, adapter.send(:translate_exception_class, active_record_error, "SELECT", [])

      old_warning_ignore = ActiveRecord.db_warnings_ignore
      ActiveRecord.db_warnings_ignore = [/ignore-me/, "123"]
      assert adapter.send(:warning_ignored?, Struct.new(:message, :code).new("ignore-me please", nil))
      assert adapter.send(:warning_ignored?, Struct.new(:message, :code).new("other", 123))
      refute adapter.send(:warning_ignored?, Struct.new(:message, :code).new("other", 456))
      ActiveRecord.db_warnings_ignore = old_warning_ignore

      populated_column = Struct.new(:auto_populated?).new(true)
      plain_column = Struct.new(:auto_populated?).new(false)
      assert_equal true, adapter.return_value_after_insert?(populated_column)
      assert_equal false, adapter.return_value_after_insert?(plain_column)

      adapter.disable_extension("uuid-ossp")
      adapter.enable_extension("uuid-ossp")
      adapter.create_enum("mood", ["ok"])
      adapter.drop_enum("mood")
      adapter.rename_enum("old", "new")
      adapter.add_enum_value("mood", "great")
      adapter.rename_enum_value("mood", "ok", "fine")
      adapter.create_virtual_table(:searches)
      adapter.drop_virtual_table(:searches)
      assert_nil adapter.get_advisory_lock(1)
      assert_nil adapter.release_advisory_lock(1)
      assert_equal "yielded", adapter.unprepared_statement { "yielded" }
      adapter.instance_variable_set(:@connected_since, 123.0)
      adapter.force_retirement
      assert_equal(-Float::INFINITY, adapter.instance_variable_get(:@connected_since))
      raw = Object.new
      adapter.instance_variable_set(:@raw_connection, raw)
      adapter.instance_variable_set(:@verified, true)
      assert_same raw, adapter.send(:any_raw_connection)
      assert_same raw, adapter.send(:valid_raw_connection)
      assert_same raw, adapter.raw_connection
      assert adapter.instance_variable_get(:@raw_connection_dirty)
      adapter.define_singleton_method(:active?) { true }
      adapter.instance_variable_set(:@verified, false)
      adapter.verify
      assert adapter.verified?
      assert_nil adapter.reset!

      reconnect_calls = 0
      adapter.define_singleton_method(:reconnect) { reconnect_calls += 1 }
      adapter.define_singleton_method(:enable_lazy_transactions!) { @lazy_transactions_enabled = true }
      adapter.define_singleton_method(:reset_transaction) { |restore: false, &block| @restore_transactions = restore; block&.call }
      adapter.define_singleton_method(:clear_cache!) { |new_connection: false| @cache_cleared_with_new_connection = new_connection }
      adapter.define_singleton_method(:configure_connection) { @configured_after_reconnect = true }
      assert_equal true, adapter.reconnect!(restore_transactions: true)
      assert_equal 1, reconnect_calls
      assert adapter.instance_variable_get(:@lazy_transactions_enabled)
      assert adapter.instance_variable_get(:@cache_cleared_with_new_connection)
      assert adapter.instance_variable_get(:@configured_after_reconnect)
      assert adapter.instance_variable_get(:@restore_transactions)

      current_transaction = Struct.new(:invalidated) do
        def invalidated? = invalidated
        def invalidate! = self.invalidated = true
      end.new(false)
      adapter.define_singleton_method(:current_transaction) { current_transaction }
      savepoint_errors_invalidate = true
      adapter.define_singleton_method(:savepoint_errors_invalidate_transactions?) { savepoint_errors_invalidate }
      adapter.send(:invalidate_transaction, ActiveRecord::StatementInvalid.new("boom"))
      refute current_transaction.invalidated?
      adapter.send(:invalidate_transaction, ActiveRecord::TransactionRollbackError.new("rollback"))
      assert current_transaction.invalidated?
      savepoint_errors_invalidate = false
      current_transaction.invalidated = false
      adapter.send(:invalidate_transaction, ActiveRecord::TransactionRollbackError.new("rollback"))
      refute current_transaction.invalidated?
      savepoint_errors_invalidate = true
      current_transaction.invalidated = true
      refute adapter.send(:retryable_query_error?, ActiveRecord::StatementInvalid.new("boom"))

      assert_equal "INSERT INTO posts (id) VALUES (1)", adapter.build_insert_sql(Struct.new(:skip_duplicates?, :update_duplicates?, :into, :values_list).new(false, false, "INTO posts", "(id) VALUES (1)"))
      assert_raises(NotImplementedError) { adapter.build_insert_sql(Struct.new(:skip_duplicates?, :update_duplicates?, :into, :values_list).new(true, false, "INTO posts", "(id) VALUES (1)")) }
      assert_nil adapter.get_database_version
      assert_nil adapter.check_version

      db_config = Struct.new(:name, :env_name).new("primary", "test")
      pool = Struct.new(:migration_context, :db_config, :role, :shard, :checked_in) do
        def server_version(_connection) = "1.2.3"
        def checkin(connection) = self.checked_in = connection
        def remove(connection) = self.checked_in = [:removed, connection]
      end.new(Struct.new(:current_version).new(0), db_config, :writing, :default)
      adapter.pool = pool
      assert_equal 0, adapter.schema_version
      assert_equal "1.2.3", adapter.database_version
      assert_equal :writing, adapter.role
      assert_equal :default, adapter.shard
      assert_match(/env_name="test"/, adapter.inspect)
      adapter.close
      assert_same adapter, pool.checked_in
      adapter.throw_away!
      assert_equal [:removed, adapter], pool.checked_in
      assert_equal true, adapter.database_exists?
      assert_equal false, Class.new(adapter_class) { def connect! = raise ActiveRecord::NoDatabaseError }.database_exists?({})
    ensure
      adapter_class.migration_strategy = nil if defined?(adapter_class) && adapter_class.respond_to?(:migration_strategy=)
    end

    def test_abstract_adapter_connection_lifecycle_public_contracts
      @connection.reconnect!
      assert @connection.verified?
      assert @connection.connected?

      adapter_class = Class.new(ActiveRecord::ConnectionAdapters::AbstractAdapter) do
        def self.native_database_types = { string: { name: "varchar" } }
        def columns(_table_name) = []
        def connect! = true
      end
      adapter_class.const_set(:ADAPTER_NAME, "LifecycleAbstract")

      assert_raises(ArgumentError) { adapter_class.new({}, Object.new) }

      deprecated_connection = Object.new
      deprecated = adapter_class.new(deprecated_connection, nil, { pool_jitter: 0.0 }, { replica: true, retry_deadline: "1.25" })
      assert deprecated.replica?
      assert deprecated.preventing_writes?
      assert_equal 1.25, deprecated.retry_deadline
      assert_operator deprecated.pool_jitter(10.0), :<=, 10.0
      assert_operator deprecated.pool_jitter(10.0), :>=, 0.0
      assert_same deprecated_connection, deprecated.instance_variable_get(:@unconfigured_connection)

      primary_config = Struct.new(:name, :env_name).new("primary", "test")
      named_config = Struct.new(:name, :env_name).new("animals", "test")
      pool_class = Struct.new(:db_config, :role, :shard) do
        def schema_cache = nil
        def schema_reflection = nil
        def connection_descriptor = nil
      end
      default_pool = pool_class.new(primary_config, :writing, :default)
      named_pool = pool_class.new(named_config, :reading, :shard_one)

      adapter = adapter_class.new({ pool_jitter: 0.0, prepared_statements: true })
      adapter.pool = default_pool
      adapter.unprepared_statement do
        refute adapter.prepared_statements?
      end
      assert adapter.prepared_statements?
      assert_no_match(/ name=/, adapter.inspect)
      assert_no_match(/ shard=/, adapter.inspect)
      adapter.pool = named_pool
      assert_match(/name="animals"/, adapter.inspect)
      assert_match(/shard=:shard_one/, adapter.inspect)

      adapter.lock_thread = Thread.current
      assert_kind_of ActiveSupport::Concurrency::ThreadMonitor, adapter.instance_variable_get(:@lock)
      adapter.lock_thread = Fiber.current
      assert_instance_of Monitor, adapter.instance_variable_get(:@lock)

      adapter.instance_variable_set(:@owner, ActiveSupport::IsolatedExecutionState.context)
      assert adapter.in_use?
      assert_equal 0, adapter.seconds_idle
      adapter.instance_variable_set(:@raw_connection, Object.new)
      adapter.instance_variable_set(:@last_activity, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      adapter.instance_variable_set(:@connected_since, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 1)
      assert_operator adapter.seconds_since_last_activity, :>=, 0
      assert_operator adapter.connection_age, :>=, 0

      adapter.define_singleton_method(:enable_lazy_transactions!) { @lazy_enabled_by_expire = true }
      adapter.define_singleton_method(:unset_query_cache!) { @query_cache_unset = true }
      adapter.expire(false)
      refute adapter.in_use?
      assert adapter.instance_variable_get(:@lazy_enabled_by_expire)
      assert adapter.instance_variable_get(:@query_cache_unset)

      assert_raises(ActiveRecord::ActiveRecordError) { adapter.expire }
      assert_raises(ActiveRecord::ActiveRecordError) { adapter.steal! }
    end

    def test_savepoint_public_methods_issue_transaction_commands
      commands = []
      transaction = Struct.new(:savepoint_name).new("active_record_test_savepoint")

      @connection.stub(:current_transaction, transaction) do
        @connection.stub(:query_command, ->(sql, name) { commands << [sql, name] }) do
          assert_equal "active_record_test_savepoint", @connection.current_savepoint_name
          @connection.create_savepoint
          @connection.exec_rollback_to_savepoint("custom_savepoint")
          @connection.release_savepoint
        end
      end

      assert_equal [
        ["SAVEPOINT active_record_test_savepoint", "TRANSACTION"],
        ["ROLLBACK TO SAVEPOINT custom_savepoint", "TRANSACTION"],
        ["RELEASE SAVEPOINT active_record_test_savepoint", "TRANSACTION"],
      ], commands
    end

    def test_database_statements_public_query_helpers_and_defaults
      assert_equal "SELECT 1", @connection.to_sql("SELECT 1")
      assert_equal 1, @connection.select_value("SELECT 1 AS value")
      assert_equal [1], @connection.select_values("SELECT 1 AS value")
      assert_equal [1], @connection.select_one("SELECT 1 AS value").values
      assert_equal [[1]], @connection.select_rows("SELECT 1 AS value")
      assert_equal 1, @connection.query_value("SELECT 1 AS value")
      assert_equal [1], @connection.query_values("SELECT 1 AS value")
      assert_equal [1], @connection.query_one("SELECT 1 AS value").values
      assert_equal [[1]], @connection.query_rows("SELECT 1 AS value")

      assert_nil @connection.default_sequence_name("topics", "id")
      assert_equal "DEFAULT VALUES", @connection.empty_insert_statement_value
      assert_equal "plain", @connection.send(:with_yaml_fallback, "plain")
      assert_match(/foo:/, @connection.send(:with_yaml_fallback, { foo: "bar" }))
      assert @connection.high_precision_current_timestamp

      transaction_value = nil
      @connection.transaction { transaction_value = @connection.select_value("SELECT 1") }
      assert_equal 1, transaction_value
      assert_includes [true, false], @connection.transaction_open?
      assert_nothing_raised { @connection.reset_sequence!("topics", "id") }
      assert_nothing_raised { @connection.execute_batch(["SELECT 1"], "Database Statements Batch") }
    end

    def test_database_statements_abstract_contract_defaults
      transaction = Struct.new(:open?, keyword_init: true)
      manager = Struct.new(:current_transaction, keyword_init: true)
      klass = Class.new do
        include ActiveRecord::ConnectionAdapters::DatabaseStatements

        define_method(:reset_transaction) { |*| @reset_transaction_called = true }
        def reset_transaction_called? = @reset_transaction_called
        define_method(:transaction_manager) { manager.new(current_transaction: transaction.new(open?: false)) }
        def pool = ActiveRecord::Base.connection_pool
        def execute_intent(intent) = (intent.raw_result = :ok)
        def affected_rows(raw_result) = 0
      end
      statements = klass.new

      assert_predicate statements, :reset_transaction_called?
      assert_raises(NotImplementedError) { statements.write_query?("SELECT 1") }
      assert_raises(NotImplementedError) { statements.explain("SELECT 1") }
      assert_raises(ActiveRecord::TransactionIsolationError) { statements.begin_isolated_db_transaction(:serializable) }
      assert_nil statements.begin_db_transaction
      assert_nil statements.commit_db_transaction
      assert_nil statements.exec_rollback_db_transaction
      assert_nil statements.exec_restart_db_transaction
      assert_nil statements.reset_isolation_level
      assert_equal ["SELECT 1"], statements.execute_batch(["SELECT 1"], "Dummy Batch", materialize_transactions: false)
      assert_equal Arel.sql("CURRENT_TIMESTAMP", retryable: true), statements.high_precision_current_timestamp
      assert_equal Arel.sql("DEFAULT"), statements.send(:default_insert_value, nil)
    end

    def test_query_cache_store_contract
      version = Concurrent::AtomicFixnum.new
      store = ActiveRecord::ConnectionAdapters::QueryCache::Store.new(version, 2)

      assert_not store.enabled?
      assert store.dirties?
      assert_predicate store, :empty?
      assert_equal 0, store.size
      assert_equal "uncached", store.compute_if_absent("a") { "uncached" }
      assert_nil store["a"]

      store.enabled = true
      assert_equal "first", store.compute_if_absent("a") { "first" }
      assert_equal "first", store.compute_if_absent("a") { flunk("cached entry should be reused") }
      assert_equal "first", store["a"]
      store.compute_if_absent("b") { "second" }
      store.compute_if_absent("c") { "third" }
      assert_nil store["a"]
      assert_equal 2, store.size

      version.increment
      assert_predicate store, :empty?
      assert_same store, store.clear

      registry = ActiveRecord::ConnectionAdapters::QueryCache::QueryCacheRegistry.new
      context = Object.new
      first_cache = registry.compute_if_absent(context) { :first_cache }
      assert_equal :first_cache, first_cache
      assert_equal :first_cache, registry.compute_if_absent(context) { flunk("registered cache should be reused") }
      clearable_map = Class.new do
        def synchronize
          yield
        end

        def clear
          @cleared = true
        end

        def cleared? = @cleared
      end.new
      registry.instance_variable_set(:@map, clearable_map)
      registry.clear
      assert clearable_map.cleared?

      pool_config = Struct.new(:query_cache)
      pool_class = Class.new do
        include ActiveRecord::ConnectionAdapters::QueryCache::ConnectionPoolConfiguration
        attr_reader :db_config

        define_method(:initialize) do |query_cache|
          @db_config = pool_config.new(query_cache)
          super()
        end
      end

      assert_nil pool_class.new(false).instance_variable_get(:@query_cache_max_size)
      assert_nil pool_class.new(0).instance_variable_get(:@query_cache_max_size)
      assert_nil pool_class.new("custom").instance_variable_get(:@query_cache_max_size)
      assert_equal 7, pool_class.new(7).instance_variable_get(:@query_cache_max_size)
      assert_equal ActiveRecord::ConnectionAdapters::QueryCache::DEFAULT_SIZE, pool_class.new(nil).instance_variable_get(:@query_cache_max_size)

      nil_db_config_pool_class = Class.new do
        include ActiveRecord::ConnectionAdapters::QueryCache::ConnectionPoolConfiguration
        def db_config = nil
      end
      assert_equal ActiveRecord::ConnectionAdapters::QueryCache::DEFAULT_SIZE, nil_db_config_pool_class.new.instance_variable_get(:@query_cache_max_size)
    end

    def test_query_cache_connection_and_pool_contract
      pool = @connection.pool
      original_cache = @connection.query_cache

      assert_not @connection.query_cache_enabled
      @connection.cache do
        assert @connection.query_cache_enabled
        assert pool.query_cache_enabled
        assert pool.dirties_query_cache
      end
      assert_not @connection.query_cache_enabled

      @connection.uncached(dirties: false) do
        assert_not @connection.query_cache_enabled
        assert_not pool.dirties_query_cache
      end
      assert pool.dirties_query_cache

      @connection.enable_query_cache!
      assert @connection.query_cache_enabled
      @connection.disable_query_cache!
      assert_not @connection.query_cache_enabled

      @connection.query_cache = nil
      assert_nil @connection.query_cache
      assert_nil @connection.query_cache_enabled
      @connection.query_cache = original_cache
      assert_same original_cache, @connection.query_cache

      @connection.instance_variable_set(:@pinned, true)
      @connection.instance_variable_set(:@owner, Object.new)
      assert_same pool.query_cache, @connection.query_cache
    ensure
      @connection.instance_variable_set(:@pinned, false)
      @connection.query_cache = original_cache if defined?(original_cache)
      @connection.disable_query_cache!
    end

    def test_query_cache_caches_selects_and_reports_cached_notifications
      cached_notifications = []
      subscriber = lambda do |_name, _started, _finished, _id, payload|
        cached_notifications << payload if payload[:cached]
      end

      @connection.clear_query_cache
      @connection.cache do
        ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
          first = @connection.select_all("SELECT 1 AS value", "Query Cache Test")
          looked_up = @connection.send(:lookup_sql_cache, "SELECT 1 AS value", "Query Cache Test", [])
          missed_with_binds = @connection.send(:lookup_sql_cache, "SELECT 1 AS value", "Query Cache Test", [:bind])
          bound_result = @connection.send(:cache_sql, "SELECT 2 AS value", "Query Cache Test", [:bind]) do
            ActiveRecord::Result.new(["value"], [[2]])
          end
          bound_lookup = @connection.send(:lookup_sql_cache, "SELECT 2 AS value", "Query Cache Test", [:bind])
          second = @connection.select_all("SELECT 1 AS value", "Query Cache Test")
          future = @connection.select_all("SELECT 1 AS value", "Query Cache Test", async: true)

          assert_equal first.rows, looked_up.rows
          assert_nil missed_with_binds
          assert_equal [[2]], bound_result.rows
          assert_equal [[2]], bound_lookup.rows
          assert_equal first.rows, second.rows
          assert_equal first.rows, future.result.rows
        end
      end

      assert_operator cached_notifications.length, :>=, 1
      payload = cached_notifications.first
      assert_equal "SELECT 1 AS value", payload[:sql]
      assert_equal "Query Cache Test", payload[:name]
      assert_equal 1, payload[:row_count]
      assert_equal [], payload[:binds]
      assert_equal [], payload[:type_casted_binds].call
      assert_same @connection, payload[:connection]
    ensure
      @connection.clear_query_cache
      @connection.disable_query_cache!
    end

    def test_schema_creation_builds_create_table_index_and_alter_sql
      td = @connection.send(:create_table_definition, "schema_creation_posts", temporary: true, if_not_exists: true, options: "WITHOUT ROWID")
      td.column :title, :string, default: "hello", null: false
      td.column :rank, :integer, primary_key: true
      td.primary_keys [:id, :tenant_id]
      td.foreign_key :authors, column: :author_id, primary_key: :id, name: "fk_schema_creation", on_delete: :cascade, on_update: :nullify
      td.check_constraint "rank > 0", name: "chk_schema_creation_rank"

      create_sql = @connection.schema_creation.accept(td)
      assert_includes create_sql, "CREATE TEMPORARY TABLE IF NOT EXISTS"
      assert_includes create_sql, "schema_creation_posts"
      assert_includes create_sql, "DEFAULT 'hello' NOT NULL"
      assert_includes create_sql, "PRIMARY KEY"
      assert_includes create_sql, "PRIMARY KEY"
      assert_includes create_sql, "FOREIGN KEY"
      assert_includes create_sql, "ON DELETE CASCADE"
      assert_includes create_sql, "ON UPDATE SET NULL"
      assert_includes create_sql, "CHECK (rank > 0)"
      assert_includes create_sql, "WITHOUT ROWID"

      index = ActiveRecord::ConnectionAdapters::IndexDefinition.new(
        "schema_creation_posts", "index_schema_creation_posts_on_title", true, ["title"],
        orders: { "title" => :desc }, where: "title IS NOT NULL"
      )
      index_sql = @connection.schema_creation.accept(
        ActiveRecord::ConnectionAdapters::CreateIndexDefinition.new(index, "CONCURRENTLY", true, nil)
      )
      assert_includes index_sql, "CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS"
      assert_includes index_sql, "index_schema_creation_posts_on_title"
      assert_includes index_sql, "title"
      assert_includes index_sql, "WHERE title IS NOT NULL"

      alter = @connection.send(:create_alter_table, "schema_creation_posts")
      alter.add_column :body, :text, null: false
      alter.add_foreign_key :authors, column: :author_id, primary_key: :id, name: "fk_schema_creation_alter", on_delete: :restrict
      alter.drop_foreign_key "fk_schema_creation_old"
      alter.add_check_constraint "length(body) > 0", name: "chk_schema_creation_body"
      alter.drop_check_constraint "chk_schema_creation_old"
      alter.drop_constraint "constraint_schema_creation_old"

      alter_sql = @connection.schema_creation.accept(alter)
      assert_includes alter_sql, "ALTER TABLE"
      assert_includes alter_sql, "ADD"
      assert_includes alter_sql, "ON DELETE RESTRICT"
      assert_includes alter_sql, "DROP CONSTRAINT"
    end

    def test_schema_creation_abstract_feature_branches_and_helpers
      fake_connection = Class.new do
        def quote_column_name(name) = %Q("#{name}")
        def quote_table_name(name) = %Q("#{name}")
        def quote_default_expression(value, _column) = value.inspect
        def type_to_sql(type, **options) = [type.to_s.upcase, options[:limit]].compact.join("(").then { |sql| options[:limit] ? "#{sql})" : sql }
        def options_include_default?(options) = options.key?(:default)
        def supports_indexes_in_create? = true
        def use_foreign_keys? = false
        def quoted_columns_for_index(columns, _options) = Array(columns).map { |column| %Q("#{column}") }
        def supports_partial_index? = true
        def supports_check_constraints? = true
        def supports_index_include? = true
        def supports_exclusion_constraints? = true
        def supports_unique_constraints? = true
        def supports_nulls_not_distinct? = true
        def lookup_cast_type(sql_type) = sql_type
        def valid_column_definition_options = ActiveRecord::ConnectionAdapters::ColumnDefinition::OPTION_NAMES + [:auto_increment]
        def supports_datetime_with_precision? = false
        def foreign_key_options(_from, to, options) = options.reverse_merge(column: "#{to.to_s.singularize}_id", primary_key: "id", name: "fk_#{to}")
        def check_constraint_options(_table, expression, options) = options.reverse_merge(name: "chk_#{expression.hash.abs}")
      end.new
      schema = ActiveRecord::ConnectionAdapters::SchemaCreation.new(fake_connection)
      schema.define_singleton_method(:index_in_create) do |table_name, column_name, options|
        "INLINE INDEX #{table_name}(#{Array(column_name).join(',')}) #{options[:name]}"
      end
      schema.define_singleton_method(:quoted_include_columns) { |columns| Array(columns).map { |column| %Q("#{column}") }.join(", ") }
      schema.define_singleton_method(:to_sql) { |sql| super(sql) }

      table_definition = ActiveRecord::ConnectionAdapters::TableDefinition.new(fake_connection, "feature_posts", as: Object.new.tap { |o| def o.to_sql = "SELECT 1 AS id" })
      table_definition.column :title, :string, index: { name: "inline_title" }
      table_definition.column :serial, :integer, auto_increment: true, primary_key: true, _skip_validate_options: true
      table_definition.define_singleton_method(:exclusion_constraints) { [] }
      table_definition.define_singleton_method(:unique_constraints) { [] }

      create_sql = schema.accept(table_definition)
      assert_includes create_sql, "INLINE INDEX feature_posts(title) inline_title"
      assert_includes create_sql, "AS SELECT 1 AS id"

      index = ActiveRecord::ConnectionAdapters::IndexDefinition.new(
        "feature_posts", "idx_feature_posts", true, "LOWER(title)",
        type: "FULLTEXT", using: "gin", include: ["id"], nulls_not_distinct: true, where: "title IS NOT NULL"
      )
      index_sql = schema.accept(ActiveRecord::ConnectionAdapters::CreateIndexDefinition.new(index, "ALGORITHM", true, nil))
      assert_includes index_sql, "USING gin"
      assert_includes index_sql, "INCLUDE (\"id\")"
      assert_includes index_sql, "NULLS NOT DISTINCT"

      no_feature_connection = Class.new do
        def quote_column_name(name) = %Q("#{name}")
        def quote_table_name(name) = %Q("#{name}")
        def type_to_sql(type, **) = type.to_s.upcase
        def supports_indexes_in_create? = false
        def use_foreign_keys? = false
        def supports_check_constraints? = false
        def supports_exclusion_constraints? = false
        def supports_unique_constraints? = false
      end.new
      no_feature_table = ActiveRecord::ConnectionAdapters::TableDefinition.new(no_feature_connection, "empty_feature_posts", as: "SELECT 1 AS id")
      no_feature_sql = ActiveRecord::ConnectionAdapters::SchemaCreation.new(no_feature_connection).accept(no_feature_table)
      assert_equal 'CREATE TABLE "empty_feature_posts"  AS SELECT 1 AS id', no_feature_sql

      assert_equal "ON UPDATE SET NULL", schema.send(:action_sql, "UPDATE", :nullify)
      assert_equal "ON UPDATE CASCADE", schema.send(:action_sql, "UPDATE", :cascade)
      assert_equal "ON UPDATE RESTRICT", schema.send(:action_sql, "UPDATE", :restrict)
      assert_raises(ArgumentError) { schema.send(:action_sql, "UPDATE", :explode) }
    end

    def test_invalid_column
      assert_not @connection.valid_type?(:foobar)
      assert_not @connection.class.valid_type?(:foobar)
    end

    def test_tables
      tables = @connection.tables
      assert_includes tables, "accounts"
      assert_includes tables, "authors"
      assert_includes tables, "tasks"
      assert_includes tables, "topics"
    end

    def test_table_exists?
      assert @connection.table_exists?("accounts")
      assert @connection.table_exists?(:accounts)
      assert_not @connection.table_exists?("nonexistingtable")
      assert_not @connection.table_exists?("'")
      assert_not @connection.table_exists?(nil)
    end

    def test_data_sources
      data_sources = @connection.data_sources
      assert_includes data_sources, "accounts"
      assert_includes data_sources, "authors"
      assert_includes data_sources, "tasks"
      assert_includes data_sources, "topics"
    end

    def test_data_source_exists?
      assert @connection.data_source_exists?("accounts")
      assert @connection.data_source_exists?(:accounts)
      assert_not @connection.data_source_exists?("nonexistingtable")
      assert_not @connection.data_source_exists?("'")
      assert_not @connection.data_source_exists?(nil)
    end

    def test_indexes
      idx_name = "accounts_idx"

      indexes = @connection.indexes("accounts")
      assert_empty indexes

      @connection.add_index :accounts, :firm_id, name: idx_name
      indexes = @connection.indexes("accounts")
      assert_equal "accounts", indexes.first.table
      assert_equal idx_name, indexes.first.name
      assert_not indexes.first.unique
      assert_equal ["firm_id"], indexes.first.columns
    ensure
      @connection.remove_index(:accounts, name: idx_name) rescue nil
    end

    def test_returns_empty_indexes_for_non_existing_table
      assert_equal [], @connection.indexes("nonexistingtable")
    end

    def test_remove_index_when_name_and_wrong_column_name_specified
      index_name = "accounts_idx"

      @connection.add_index :accounts, :firm_id, name: index_name
      assert_raises ArgumentError do
        @connection.remove_index :accounts, name: index_name, column: :wrong_column_name
      end
    ensure
      @connection.remove_index(:accounts, name: index_name)
    end

    def test_remove_index_when_name_and_wrong_column_name_specified_positional_argument
      index_name = "accounts_idx"

      @connection.add_index :accounts, :firm_id, name: index_name
      assert_raises ArgumentError do
        @connection.remove_index :accounts, :wrong_column_name, name: index_name
      end
    ensure
      @connection.remove_index(:accounts, name: index_name)
    end

    def test_current_database
      if @connection.respond_to?(:current_database)
        assert_equal ARTest.test_configuration_hashes["arunit"]["database"], @connection.current_database
      else
        skip
      end
    end

    test "#exec_query queries with no result set return an empty ActiveRecord::Result" do
      result = @connection.exec_query "INSERT INTO subscribers(nick) VALUES('me')"
      assert_instance_of(ActiveRecord::Result, result)
      assert_empty result.rows
      assert_empty result.columns
    end

    test "#exec_query queries with an empty result set still return the columns" do
      result = @connection.exec_query "SELECT * FROM subscribers WHERE 1=0"
      assert_instance_of(ActiveRecord::Result, result)
      assert_empty result.rows
      assert_not_empty result.columns
    end

    test "#exec_query queries return an ActiveRecord::Result with affected rows" do
      result = @connection.exec_query "INSERT INTO subscribers(nick, name) VALUES('me', 'me'), ('you', 'you')"
      assert_equal 2, result.affected_rows

      update_result = @connection.exec_query "UPDATE subscribers SET name = 'you' WHERE name = 'me'"
      assert_equal 1, update_result.affected_rows

      select_result = @connection.exec_query "SELECT * FROM subscribers"
      assert_not_equal update_result.affected_rows, select_result.affected_rows

      result = @connection.exec_query "DELETE FROM subscribers WHERE name = 'you'"
      assert_equal 2, result.affected_rows

      result = @connection.exec_query "DELETE FROM subscribers WHERE name = 'you'"
      assert_equal 0, result.affected_rows
    end

    if current_adapter?(:Mysql2Adapter, :TrilogyAdapter)
      def test_charset
        assert_not_nil @connection.charset
        assert_not_equal "character_set_database", @connection.charset
        assert_equal @connection.show_variable("character_set_database"), @connection.charset
      end

      def test_collation
        assert_not_nil @connection.collation
        assert_not_equal "collation_database", @connection.collation
        assert_equal @connection.show_variable("collation_database"), @connection.collation
      end

      def test_show_nonexistent_variable_returns_nil
        assert_nil @connection.show_variable("foo_bar_baz")
      end

      def test_not_specifying_database_name_for_cross_database_selects
        assert_nothing_raised do
          db_config = ActiveRecord::Base.configurations.configs_for(env_name: "arunit", name: "primary")
          ActiveRecord::Base.establish_connection(db_config.configuration_hash.except(:database))

          config = ARTest.test_configuration_hashes
          ActiveRecord::Base.lease_connection.execute(
            "SELECT #{config['arunit']['database']}.pirates.*, #{config['arunit2']['database']}.courses.* " \
            "FROM #{config['arunit']['database']}.pirates, #{config['arunit2']['database']}.courses"
          )
        end
      ensure
        ActiveRecord::Base.establish_connection :arunit
      end
    end

    unless in_memory_db? || current_adapter?(:TrilogyAdapter)
      def test_disable_prepared_statements
        original_prepared_statements = ActiveRecord.disable_prepared_statements
        db_config = ActiveRecord::Base.configurations.configs_for(env_name: "arunit", name: "primary")
        ActiveRecord::Base.establish_connection(db_config.configuration_hash.merge(prepared_statements: true))

        assert_predicate ActiveRecord::Base.lease_connection, :prepared_statements?

        ActiveRecord.disable_prepared_statements = true
        ActiveRecord::Base.establish_connection(db_config.configuration_hash.merge(prepared_statements: true))
        assert_not_predicate ActiveRecord::Base.lease_connection, :prepared_statements?
      ensure
        ActiveRecord.disable_prepared_statements = original_prepared_statements
        ActiveRecord::Base.establish_connection :arunit
      end
    end

    def test_table_alias
      def @connection.test_table_alias_length() 10; end
      class << @connection
        alias_method :old_table_alias_length, :table_alias_length
        alias_method :table_alias_length,     :test_table_alias_length
      end

      assert_equal "posts",      @connection.table_alias_for("posts")
      assert_equal "posts_comm", @connection.table_alias_for("posts_comments")
      assert_equal "dbo_posts",  @connection.table_alias_for("dbo.posts")

      class << @connection
        remove_method :table_alias_length
        alias_method :table_alias_length, :old_table_alias_length
      end
    end

    def test_uniqueness_violations_are_translated_to_specific_exception
      @connection.execute "INSERT INTO subscribers(nick) VALUES('me')"
      error = assert_raises(ActiveRecord::RecordNotUnique) do
        @connection.execute "INSERT INTO subscribers(nick) VALUES('me')"
      end

      assert_not_nil error.cause
    end

    def test_not_null_violations_are_translated_to_specific_exception
      error = assert_raises(ActiveRecord::NotNullViolation) do
        Post.create
      end

      assert_not_nil error.cause
    end

    unless current_adapter?(:SQLite3Adapter)
      def test_value_limit_violations_are_translated_to_specific_exception
        error = assert_raises(ActiveRecord::ValueTooLong) do
          Event.create(title: "abcdefgh")
        end

        assert_not_nil error.cause
      end

      def test_numeric_value_out_of_ranges_are_translated_to_specific_exception
        error = assert_raises(ActiveRecord::RangeError) do
          Book.lease_connection.create("INSERT INTO books(author_id) VALUES (9223372036854775808)")
        end

        assert_not_nil error.cause
      end
    end

    def test_exceptions_from_notifications_are_not_translated
      original_error = StandardError.new("This StandardError shouldn't get translated")
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") { raise original_error }
      actual_error = assert_raises(StandardError) do
        @connection.execute("SELECT * FROM posts")
      end
      assert_equal original_error, actual_error

    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
    end

    def test_database_related_exceptions_are_translated_to_statement_invalid
      error = assert_raises(ActiveRecord::StatementInvalid) do
        @connection.execute("This is a syntax error")
      end

      assert_instance_of ActiveRecord::StatementInvalid, error
      assert_kind_of Exception, error.cause
    end

    def test_select_all_always_return_activerecord_result
      result = @connection.select_all "SELECT * FROM posts"
      assert result.is_a?(ActiveRecord::Result)
    end

    if ActiveRecord::Base.lease_connection.prepared_statements
      def test_select_all_insert_update_delete_with_casted_binds
        binds = [Event.type_for_attribute("id").serialize(1)]
        bind_param = Arel::Nodes::BindParam.new(nil)

        id = @connection.insert("INSERT INTO events(id) VALUES (#{bind_param.to_sql})", nil, nil, nil, nil, binds)
        assert_equal 1, id

        updated = @connection.update("UPDATE events SET title = 'foo' WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_equal 1, updated

        result = @connection.select_all("SELECT * FROM events WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_equal({ "id" => 1, "title" => "foo" }, result.first)

        deleted = @connection.delete("DELETE FROM events WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_equal 1, deleted

        result = @connection.select_all("SELECT * FROM events WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_nil result.first
      end

      def test_select_all_insert_update_delete_with_binds
        binds = [Relation::QueryAttribute.new("id", 1, Event.type_for_attribute("id"))]
        bind_param = Arel::Nodes::BindParam.new(nil)

        id = @connection.insert("INSERT INTO events(id) VALUES (#{bind_param.to_sql})", nil, nil, nil, nil, binds)
        assert_equal 1, id

        updated = @connection.update("UPDATE events SET title = 'foo' WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_equal 1, updated

        result = @connection.select_all("SELECT * FROM events WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_equal({ "id" => 1, "title" => "foo" }, result.first)

        deleted = @connection.delete("DELETE FROM events WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_equal 1, deleted

        result = @connection.select_all("SELECT * FROM events WHERE id = #{bind_param.to_sql}", nil, binds)
        assert_nil result.first
      end
    end

    def test_select_methods_passing_a_association_relation
      author = Author.create!(name: "john")
      Post.create!(author: author, title: "foo", body: "bar")
      query = author.posts.where(title: "foo").select(:title)
      assert_equal({ "title" => "foo" }, @connection.select_one(query))
      assert @connection.select_all(query).is_a?(ActiveRecord::Result)
      assert_equal "foo", @connection.select_value(query)
      assert_equal ["foo"], @connection.select_values(query)
    end

    def test_select_methods_passing_a_relation
      Post.create!(title: "foo", body: "bar")
      query = Post.where(title: "foo").select(:title)
      assert_equal({ "title" => "foo" }, @connection.select_one(query))
      assert @connection.select_all(query).is_a?(ActiveRecord::Result)
      assert_equal "foo", @connection.select_value(query)
      assert_equal ["foo"], @connection.select_values(query)
    end

    test "type_to_sql returns a String for unmapped types" do
      assert_equal "special_db_type", @connection.type_to_sql(:special_db_type)
    end

    test "inspect does not show secrets" do
      output = @connection.inspect

      assert_match(/ActiveRecord::ConnectionAdapters::\w+:0x[\da-f]+ env_name="\w+" role=:writing>/, output)
    end

    private
      def assert_ractor_shareable(obj)
        # rubocop:disable Minitest/AssertWithExpectedArgument
        assert(Ractor.shareable?(obj), -> { "Expected #{obj} to be shareable, but it wasn't" })
        # rubocop:enable Minitest/AssertWithExpectedArgument
      end
  end

  class AdapterForeignKeyTest < ActiveRecord::TestCase
    self.use_transactional_tests = false

    fixtures :fk_test_has_pk

    def setup
      @connection = ActiveRecord::Base.lease_connection
    end

    def test_foreign_key_violations_are_translated_to_specific_exception_with_validate_false
      klass_has_fk = Class.new(ActiveRecord::Base) do
        self.table_name = "fk_test_has_fk"
      end

      error = assert_raises(ActiveRecord::InvalidForeignKey) do
        has_fk = klass_has_fk.new
        has_fk.fk_id = 1231231231
        has_fk.save(validate: false)
      end

      assert_not_nil error.cause
    end

    def test_foreign_key_violations_on_insert_are_translated_to_specific_exception
      error = assert_raises(ActiveRecord::InvalidForeignKey) do
        insert_into_fk_test_has_fk
      end

      assert_not_nil error.cause
    end

    def test_foreign_key_violations_on_delete_are_translated_to_specific_exception
      insert_into_fk_test_has_fk fk_id: 1

      error = assert_raises(ActiveRecord::InvalidForeignKey) do
        @connection.execute "DELETE FROM fk_test_has_pk WHERE pk_id = 1"
      end

      assert_not_nil error.cause
    end

    def test_disable_referential_integrity
      assert_nothing_raised do
        @connection.disable_referential_integrity do
          insert_into_fk_test_has_fk
          # should delete created record as otherwise disable_referential_integrity will try to enable constraints
          # after executed block and will fail (at least on Oracle)
          @connection.execute "DELETE FROM fk_test_has_fk"
        end
      end
    end

    private
      def insert_into_fk_test_has_fk(fk_id: 0)
        # Oracle adapter uses prefetched primary key values from sequence and passes them to connection adapter insert method
        if @connection.prefetch_primary_key?
          id_value = @connection.next_sequence_value(@connection.default_sequence_name("fk_test_has_fk", "id"))
          @connection.execute "INSERT INTO fk_test_has_fk (id,fk_id) VALUES (#{id_value},#{fk_id})"
        else
          @connection.execute "INSERT INTO fk_test_has_fk (fk_id) VALUES (#{fk_id})"
        end
      end
  end

  class AdapterTestWithoutTransaction < ActiveRecord::TestCase
    self.use_transactional_tests = false

    fixtures :posts, :authors, :author_addresses

    def setup
      @connection = ActiveRecord::Base.lease_connection
    end

    def test_create_with_query_cache
      @connection.enable_query_cache!

      count = Post.count

      @connection.create("INSERT INTO posts(title, body) VALUES ('', '')")

      assert_equal count + 1, Post.count
    ensure
      reset_fixtures("posts")
      @connection.disable_query_cache!
    end

    def test_truncate
      assert_operator Post.count, :>, 0

      @connection.truncate("posts")

      assert_equal 0, Post.count
    ensure
      reset_fixtures("posts")
    end

    def test_truncate_with_query_cache
      @connection.enable_query_cache!

      assert_operator Post.count, :>, 0

      @connection.truncate("posts")

      assert_equal 0, Post.count
    ensure
      reset_fixtures("posts")
      @connection.disable_query_cache!
    end

    def test_truncate_tables
      assert_operator Post.count, :>, 0
      assert_operator Author.count, :>, 0
      assert_operator AuthorAddress.count, :>, 0

      @connection.truncate_tables("author_addresses", "authors", "posts")

      assert_equal 0, Post.count
      assert_equal 0, Author.count
      assert_equal 0, AuthorAddress.count
    ensure
      reset_fixtures("posts", "authors", "author_addresses")
    end

    def test_truncate_tables_with_query_cache
      @connection.enable_query_cache!

      assert_operator Post.count, :>, 0
      assert_operator Author.count, :>, 0
      assert_operator AuthorAddress.count, :>, 0

      @connection.truncate_tables("author_addresses", "authors", "posts")

      assert_equal 0, Post.count
      assert_equal 0, Author.count
      assert_equal 0, AuthorAddress.count
    ensure
      reset_fixtures("posts", "authors", "author_addresses")
      @connection.disable_query_cache!
    end

    def test_empty_all_tables
      assert_operator Post.count, :>, 0
      assert_operator Author.count, :>, 0
      assert_operator AuthorAddress.count, :>, 0

      @connection.empty_all_tables

      assert_equal 0, Post.count
      assert_equal 0, Author.count
      assert_equal 0, AuthorAddress.count
    ensure
      reset_fixtures("posts", "authors", "author_addresses")
    end

    def test_empty_all_tables_with_query_cache
      @connection.enable_query_cache!

      assert_operator Post.count, :>, 0
      assert_operator Author.count, :>, 0
      assert_operator AuthorAddress.count, :>, 0

      @connection.empty_all_tables

      assert_equal 0, Post.count
      assert_equal 0, Author.count
      assert_equal 0, AuthorAddress.count
    ensure
      reset_fixtures("posts", "authors", "author_addresses")
      @connection.disable_query_cache!
    end

    # test resetting sequences in odd tables in PostgreSQL
    if ActiveRecord::Base.lease_connection.respond_to?(:reset_pk_sequence!)
      require "models/movie"
      require "models/subscriber"

      def test_reset_empty_table_with_custom_pk
        Movie.delete_all
        Movie.lease_connection.reset_pk_sequence! "movies"
        assert_equal 1, Movie.create(name: "fight club").id
      end

      def test_reset_table_with_non_integer_pk
        Subscriber.delete_all
        Subscriber.lease_connection.reset_pk_sequence! "subscribers"
        sub = Subscriber.new(name: "robert drake")
        sub.id = "bob drake"
        assert_nothing_raised { sub.save! }
      end
    end

    private
      def reset_fixtures(*fixture_names)
        ActiveRecord::FixtureSet.reset_cache

        fixture_names.each do |fixture_name|
          ActiveRecord::FixtureSet.create_fixtures(FIXTURES_ROOT, fixture_name)
        end
      end
  end

  class AdapterConnectionTest < ActiveRecord::TestCase
    unless in_memory_db?
      self.use_transactional_tests = false

      fixtures :posts, :authors, :author_addresses

      def setup
        @connection = ActiveRecord::Base.lease_connection
        assert_predicate @connection, :active?
      end

      def teardown
        @connection.reconnect!
        assert_predicate @connection, :active?
        assert_not_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
      end

      test "reconnect after a disconnect" do
        @connection.disconnect!
        assert_not_predicate @connection, :active?
        @connection.reconnect!
        assert_predicate @connection, :active?
      end

      test "materialized transaction state is reset after a reconnect" do
        @connection.begin_transaction
        assert_predicate @connection, :transaction_open?
        @connection.materialize_transactions
        assert raw_transaction_open?(@connection)
        @connection.reconnect!
        assert_not_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
      end

      test "materialized transaction state can be restored after a reconnect" do
        @connection.begin_transaction
        assert_predicate @connection, :transaction_open?
        @connection.materialize_transactions
        assert raw_transaction_open?(@connection)
        @connection.reconnect!(restore_transactions: true)
        assert_predicate @connection, :transaction_open?
        assert raw_transaction_open?(@connection)
      end

      test "materialized transaction state is reset after a disconnect" do
        @connection.begin_transaction
        assert_predicate @connection, :transaction_open?
        @connection.materialize_transactions
        assert raw_transaction_open?(@connection)
        @connection.disconnect!
        assert_not_predicate @connection, :transaction_open?
      end

      test "unmaterialized transaction state is reset after a reconnect" do
        @connection.begin_transaction
        assert_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
        @connection.reconnect!
        assert_not_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
        @connection.materialize_transactions
        assert_not raw_transaction_open?(@connection)
      end

      test "unmaterialized transaction state can be restored after a reconnect" do
        @connection.begin_transaction
        assert_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
        @connection.reconnect!(restore_transactions: true)
        assert_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
        @connection.materialize_transactions
        assert raw_transaction_open?(@connection)
      end

      test "unmaterialized transaction state is reset after a disconnect" do
        @connection.begin_transaction
        assert_predicate @connection, :transaction_open?
        assert_not raw_transaction_open?(@connection)
        @connection.disconnect!
        assert_not_predicate @connection, :transaction_open?
      end

      test "active? detects remote disconnection" do
        remote_disconnect @connection
        assert_not_predicate @connection, :active?
      end

      test "active? on a 'clean' recently-used but now-failed connection detects but doesn't fix the problem" do
        remote_disconnect @connection
        @connection.clean! # this simulates a fresh checkout from the pool

        # Clean did not verify / fix the connection
        assert_not_predicate @connection, :active?

        # And nor did the above active? check
        assert_not_predicate @connection, :active?
      end

      test "verify! restores after remote disconnection" do
        remote_disconnect @connection
        @connection.verify!
        assert_predicate @connection, :active?
      end

      test "reconnect! restores after remote disconnection" do
        remote_disconnect @connection
        @connection.reconnect!
        assert_predicate @connection, :active?
      end

      test "querying a 'clean' long-failed connection restores and succeeds" do
        remote_disconnect @connection

        @connection.clean! # this simulates a fresh checkout from the pool

        # Backdate last activity to simulate a connection we haven't used in a while
        @connection.instance_variable_set(:@last_activity, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 5.minutes)

        # Clean did not verify / fix the connection
        assert_not_predicate @connection, :active?

        # Because the connection hasn't been verified since checkout,
        # and the query cannot safely be retried, the connection will be
        # verified before querying.
        Post.delete_all

        assert_predicate @connection, :active?
      end

      test "querying a 'clean' recently-used but now-failed connection skips verification" do
        remote_disconnect @connection

        @connection.clean! # this simulates a fresh checkout from the pool

        # Because the query cannot be retried, and we (mistakenly) believe the
        # connection is still good, the query will fail. This is what we want,
        # because the alternative would be excessive reverification.
        assert_raises(ActiveRecord::AdapterError) do
          Post.delete_all
        end
      end

      test "quoting a string on a 'clean' failed connection will not prevent reconnecting" do
        remote_disconnect @connection

        @connection.clean! # this simulates a fresh checkout from the pool

        # Backdate last activity to simulate a connection we haven't used in a while
        @connection.instance_variable_set(:@last_activity, Process.clock_gettime(Process::CLOCK_MONOTONIC) - 5.minutes)

        # Clean did not verify / fix the connection
        assert_not_predicate @connection, :active?

        # Quote string will not verify a broken connection (although it may
        # reconnect in some cases)
        Post.lease_connection.quote_string("")

        # Because the connection hasn't been verified since checkout,
        # and the query cannot safely be retried, the connection will be
        # verified before querying.
        Post.delete_all

        assert_predicate @connection, :active?
      end

      test "querying after a failed non-retryable query restores and succeeds" do
        Post.first # Connection verified (and prepared statement pool populated if enabled)

        remote_disconnect @connection

        assert_raises(ActiveRecord::ConnectionFailed) do
          @connection.execute("INSERT INTO posts(title, body) VALUES ('foo', 'bar')")
        end

        assert Post.first # Verifying the connection causes a reconnect and the query succeeds
        assert_predicate @connection, :active?
      end

      test "idempotent SELECT queries allow retries" do
        notifications = capture_notifications("sql.active_record") do
          assert (a = Author.first)
          assert Post.where(id: [1, 2]).first
          assert Post.where(Arel.sql("id IN (1,2)", retryable: true)).first
          assert Post.find(1)
          assert Post.find_by(title: "Welcome to the weblog")
          assert_predicate Post, :exists?
          a.books.to_a
          Author.select(:status).joins(:books).group(:status).to_a
          Author.group(:name).count
        end.select { |n| n.payload[:name] != "SCHEMA" }

        assert_equal 9, notifications.length

        notifications.each do |n|
          assert n.payload[:allow_retry], "#{n.payload[:sql]} was not retryable"
        end
      end

      test "query cacheable idempotent SELECT queries allow retries" do
        @connection.enable_query_cache!

        notifications = capture_notifications("sql.active_record") do
          assert_not_nil (a = Author.first)
          assert_not_nil Post.where(id: [1, 2]).first
          assert Post.where(Arel.sql("id IN (1,2)", retryable: true)).first
          assert_not_nil Post.find(1)
          assert_not_nil Post.find_by(title: "Welcome to the weblog")
          assert_predicate Post, :exists?
          a.books.to_a
          Author.select(:status).joins(:books).group(:status).to_a
          Author.group(:name).count
        end.select { |n| n.payload[:name] != "SCHEMA" }

        assert_equal 9, notifications.length

        notifications.each do |n|
          assert n.payload[:allow_retry], "#{n.payload[:sql]} was not retryable"
        end
      ensure
        @connection.disable_query_cache!
      end

      test "queries containing SQL fragments do not allow retries" do
        notifications = capture_notifications("sql.active_record") do
          Post.where("1 = 1").to_a
          Post.select("title AS custom_title").first
          Book.find_by("updated_at < ?", 2.weeks.ago)
        end.select { |n| n.payload[:name] != "SCHEMA" }

        assert_equal 3, notifications.length

        notifications.each do |n|
          assert_not n.payload[:allow_retry]
        end
      end

      test "queries containing SQL functions do not allow retries" do
        tags_count_attr = Post.arel_table[:tags_count]
        abs_tags_count = Arel::Nodes::NamedFunction.new("ABS", [tags_count_attr])

        notifications = capture_notifications("sql.active_record") do
          Post.where(abs_tags_count.eq(2)).first
        end.select { |n| n.payload[:name] != "SCHEMA" }

        assert_equal 1, notifications.length

        notifications.each do |n|
          assert_not n.payload[:allow_retry]
        end
      end

      test "transaction restores after remote disconnection" do
        remote_disconnect @connection
        Post.transaction do
          Post.count
        end
        assert_predicate @connection, :active?
      end

      test "active transaction is restored after remote disconnection" do
        assert_operator Post.count, :>, 0
        Post.transaction do
          @connection.materialize_transactions
          remote_disconnect @connection

          # Regular queries are not retryable, so the only abstract operation we can
          # perform here is a direct verify. The outer transaction means using another
          # here would just be a ResetParent.
          @connection.verify!

          Post.delete_all

          assert_equal 0, Post.count
          raise ActiveRecord::Rollback
        end

        # The deletion occurred within the outer transaction (which was then rolled
        # back), and not directly on the freshly-reestablished connection, so the
        # posts are still there:
        assert_operator Post.count, :>, 0
      end

      test "dirty transaction cannot be restored after remote disconnection" do
        invocations = 0
        assert_raises ActiveRecord::ConnectionFailed do
          Post.transaction do
            invocations += 1
            Post.delete_all
            remote_disconnect @connection
            Post.count
          end
        end

        assert_equal 1, invocations # the whole transaction block is not retried

        # After the (outermost) transaction block failed, the connection is
        # ready to reconnect on next use, but hasn't done so yet
        assert_not_predicate @connection, :active?
        assert_operator Post.count, :>, 0
      end

      test "can reconnect and retry queries under limit when retry deadline is set" do
        attempts = 0
        @connection.stub(:retry_deadline, 0.1) do
          @connection.send(:with_raw_connection, allow_retry: true) do
            if attempts == 0
              attempts += 1
              raise ActiveRecord::ConnectionFailed.new("Something happened to the connection")
            end
          end
        end
      end

      test "does not reconnect and retry queries when retries are disabled" do
        assert_raises(ActiveRecord::ConnectionFailed) do
          attempts = 0
          @connection.send(:with_raw_connection) do
            if attempts == 0
              attempts += 1
              raise ActiveRecord::ConnectionFailed.new("Something happened to the connection")
            end
          end
        end
      end

      test "does not reconnect and retry queries that exceed retry deadline" do
        assert_raises(ActiveRecord::ConnectionFailed) do
          attempts = 0
          @connection.stub(:retry_deadline, 0.1) do
            @connection.send(:with_raw_connection, allow_retry: true) do
              if attempts == 0
                sleep(0.2)
                attempts += 1
                raise ActiveRecord::ConnectionFailed.new("Something happened to the connection")
              end
            end
          end
        end
      end

      test "#execute is retryable" do
        initial_connection_id = connection_id_from_server(@connection)

        kill_connection_from_server(initial_connection_id)

        @connection.execute("SELECT 1", allow_retry: true)

        assert_not_equal initial_connection_id, connection_id_from_server(@connection)
      end

      test "disconnect and recover on #configure_connection failure" do
        connection = ActiveRecord::Base.connection_pool.send(:new_connection)

        failures = [ActiveRecord::ConnectionFailed.new("Oops"), ActiveRecord::ConnectionFailed.new("Oops 2")]
        connection.singleton_class.define_method(:configure_connection) do
          if error = failures.pop
            raise error
          else
            super()
          end
        end
        assert_raises ActiveRecord::ConnectionFailed do
          connection.exec_query("SELECT 1")
        end

        assert_equal [[1]], connection.exec_query("SELECT 1").rows
        assert_empty failures
      ensure
        connection&.disconnect!
      end

      test "disconnect and recover on #configure_connection timeout" do
        connection = ActiveRecord::Base.connection_pool.send(:new_connection)

        slow = [5]
        connection.singleton_class.define_method(:configure_connection) do
          if duration = slow.pop
            sleep duration
          end
          super()
        end

        assert_raises Timeout::Error do
          Timeout.timeout(0.2) do
            connection.exec_query("SELECT 1")
          end
        end

        assert_equal [[1]], connection.exec_query("SELECT 1").rows
        assert_empty slow
      ensure
        connection&.disconnect!
      end
    end
  end

  class AdapterThreadSafetyTest < ActiveRecord::TestCase
    setup do
      @threads = []
      @connection = ActiveRecord::Base.connection_pool.checkout
    end

    teardown do
      @threads.each(&:kill)
    end

    unless in_memory_db?
      test "#active? is synchronized" do
        threads(2, 25) { @connection.select_all("SELECT 1") }
        threads(2, 25) { @connection.verify! }
        threads(2, 25) { @connection.disconnect! }

        join
        pass
      end

      test "#verify! is synchronized" do
        threads(2, 25) { @connection.verify! }
        threads(2, 25) { @connection.disconnect! }

        join
        pass
      end
    end

    private
      def join
        @threads.shuffle.each(&:join)
      end

      def threads(count, times)
        @threads += count.times.map do
          Thread.new do
            times.times do
              yield
              Thread.pass
            end
          end
        end
      end
  end
end

if ActiveRecord::Base.lease_connection.supports_advisory_locks?
  class AdvisoryLocksEnabledTest < ActiveRecord::TestCase
    include ConnectionHelper

    def test_advisory_locks_enabled?
      assert_predicate ActiveRecord::Base.lease_connection, :advisory_locks_enabled?

      run_without_connection do |orig_connection|
        ActiveRecord::Base.establish_connection(
          orig_connection.merge(advisory_locks: false)
        )

        assert_not ActiveRecord::Base.lease_connection.advisory_locks_enabled?

        ActiveRecord::Base.establish_connection(
          orig_connection.merge(advisory_locks: true)
        )

        assert_predicate ActiveRecord::Base.lease_connection, :advisory_locks_enabled?
      end
    end
  end
end

if ActiveRecord::Base.lease_connection.savepoint_errors_invalidate_transactions?
  class InvalidateTransactionTest < ActiveRecord::TestCase
    def test_invalidates_transaction_on_rollback_error
      @invalidated = false
      connection = ActiveRecord::Base.lease_connection

      connection.transaction do
        connection.send(:with_raw_connection) do
          raise ActiveRecord::Deadlocked, "made-up deadlock"
        end

      rescue ActiveRecord::Deadlocked => error
        flunk("Rescuing wrong error") unless error.message == "made-up deadlock"

        @invalidated = connection.current_transaction.invalidated?
      end

      # asserting outside of the transaction to make sure we actually reach the end of the test
      # and perform the assertion
      assert @invalidated
    end
  end
end
