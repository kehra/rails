# frozen_string_literal: true

require "cases/helper"
require "active_record/errors"
require "active_record/associations/errors"

class ErrorsTest < ActiveRecord::TestCase
  def test_adapter_error_stores_connection_pool
    pool = Object.new
    error = ActiveRecord::AdapterError.new("adapter failed", connection_pool: pool)

    assert_equal "adapter failed", error.message
    assert_same pool, error.connection_pool
  end

  def test_connection_not_established_stores_and_sets_connection_pool_once
    original_pool = Object.new
    replacement_pool = Object.new
    error = ActiveRecord::ConnectionNotEstablished.new("lost", connection_pool: original_pool)

    assert_equal "lost", error.message
    assert_same original_pool, error.connection_pool
    assert_same error, error.set_pool(replacement_pool)
    assert_same original_pool, error.connection_pool

    blank_error = ActiveRecord::ConnectionNotEstablished.new
    assert_same blank_error, blank_error.set_pool(replacement_pool)
    assert_same replacement_pool, blank_error.connection_pool
  end

  def test_connection_not_defined_stores_context_without_adapter_pool
    error = ActiveRecord::ConnectionNotDefined.new("missing", connection_name: "primary", role: :writing, shard: :default)

    assert_equal "missing", error.message
    assert_equal "primary", error.connection_name
    assert_equal :writing, error.role
    assert_equal :default, error.shard
    assert_nil error.connection_pool
  end

  def test_database_connection_error_messages
    assert_equal "Database connection error", ActiveRecord::DatabaseConnectionError.new.message
    assert_equal "custom", ActiveRecord::DatabaseConnectionError.new("custom").message

    hostname_error = ActiveRecord::DatabaseConnectionError.hostname_error("db.example.test")
    assert_includes hostname_error.message, "hostname: db.example.test"
    assert_includes hostname_error.message, "valid connection"

    username_error = ActiveRecord::DatabaseConnectionError.username_error("alice")
    assert_includes username_error.message, "username: alice"
    assert_includes username_error.message, "username/password are valid"
  end

  def test_statement_invalid_stores_query_details_and_sets_query_once
    pool = Object.new
    error = ActiveRecord::StatementInvalid.new("bad sql", connection_pool: pool)

    assert_equal "bad sql", error.message
    assert_same pool, error.connection_pool
    assert_nil error.sql
    assert_nil error.binds
    assert_same error, error.set_query("SELECT 1", ["bind"])
    assert_equal "SELECT 1", error.sql
    assert_equal ["bind"], error.binds
    assert_same error, error.set_query("SELECT 2", [])
    assert_equal "SELECT 1", error.sql
    assert_equal ["bind"], error.binds

    with_cause = begin
      raise "cause message"
    rescue
      ActiveRecord::StatementInvalid.new
    end
    assert_equal "cause message", with_cause.message
  end

  def test_mismatched_foreign_key_messages_and_query_parser
    column_class = Struct.new(:type, :sql_type, :bigint) do
      def bigint?
        bigint
      end
    end
    column = column_class.new(:integer, "integer", false)
    bigint_column = column_class.new(:integer, "bigint", true)
    pool = Object.new

    detailed = ActiveRecord::MismatchedForeignKey.new(
      message: "adapter detail",
      sql: "ALTER TABLE comments",
      binds: ["bind"],
      table: "comments",
      foreign_key: "post_id",
      target_table: "posts",
      primary_key: "id",
      primary_key_column: column,
      connection_pool: pool
    )

    assert_includes detailed.message, "Column `post_id` on table `comments`"
    assert_includes detailed.message, "change the type of the `post_id` column on `comments` to be :integer"
    assert_includes detailed.message, "Original message: adapter detail"
    assert_equal "ALTER TABLE comments", detailed.sql
    assert_equal ["bind"], detailed.binds
    assert_same pool, detailed.connection_pool
    assert_same detailed, detailed.set_query("SELECT ignored", [])

    bigint = ActiveRecord::MismatchedForeignKey.new(
      table: "comments",
      foreign_key: "post_id",
      target_table: "posts",
      primary_key: "id",
      primary_key_column: bigint_column
    )
    assert_includes bigint.message, "change the type of the `post_id` column on `comments` to be :bigint"

    generic = ActiveRecord::MismatchedForeignKey.new
    assert_includes generic.message, "There is a mismatch between the foreign key and primary key column types"
    assert_same generic, generic.set_query("ALTER TABLE generic", [])
    assert_equal "ALTER TABLE generic", generic.sql

    parsed = ActiveRecord::MismatchedForeignKey.new(
      message: "parsed detail",
      query_parser: ->(sql) {
        assert_equal "ALTER TABLE parsed", sql
        {
          table: "comments",
          foreign_key: "post_id",
          target_table: "posts",
          primary_key: "id",
          primary_key_column: column,
        }
      },
      connection_pool: pool
    )
    parsed.set_backtrace ["original:1"]

    reparsed = parsed.set_query("ALTER TABLE parsed", ["parsed bind"])
    assert_instance_of ActiveRecord::MismatchedForeignKey, reparsed
    assert_not_same parsed, reparsed
    assert_equal "ALTER TABLE parsed", reparsed.sql
    assert_equal ["parsed bind"], reparsed.binds
    assert_same pool, reparsed.connection_pool
    assert_equal ["original:1"], reparsed.backtrace
    assert_includes reparsed.message, "Original message: parsed detail"
  end

  def test_no_database_error_messages
    pool = Object.new
    error = ActiveRecord::NoDatabaseError.new(nil, connection_pool: pool)

    assert_equal "Database not found", error.message
    assert_same pool, error.connection_pool
    assert_equal "custom", ActiveRecord::NoDatabaseError.new("custom").message

    db_error = ActiveRecord::NoDatabaseError.db_error("app_test")
    assert_includes db_error.message, "Database not found: app_test"
    assert_includes db_error.message, "bin/rails db:create"

    created = false
    ActiveRecord::Tasks::DatabaseTasks.stub(:create_current, -> { created = true }) do
      ActiveSupport::ActionableError.dispatch(ActiveRecord::NoDatabaseError, "Create database")
    end
    assert created
  end

  def test_record_error_initializers_store_context
    record = Object.new

    not_found = ActiveRecord::RecordNotFound.new("missing", "Post", "id", 1)
    assert_equal "missing", not_found.message
    assert_equal "Post", not_found.model
    assert_equal "id", not_found.primary_key
    assert_equal 1, not_found.id

    not_saved = ActiveRecord::RecordNotSaved.new("save failed", record)
    assert_equal "save failed", not_saved.message
    assert_same record, not_saved.record

    not_destroyed = ActiveRecord::RecordNotDestroyed.new("destroy failed", record)
    assert_equal "destroy failed", not_destroyed.message
    assert_same record, not_destroyed.record
  end

  def test_attribute_assignment_and_multiparameter_errors_store_context
    cause = StandardError.new("bad value")
    assignment_error = ActiveRecord::AttributeAssignmentError.new("assign failed", cause, "started_at")

    assert_equal "assign failed", assignment_error.message
    assert_same cause, assignment_error.exception
    assert_equal "started_at", assignment_error.attribute

    errors = [assignment_error]
    multiparameter_error = ActiveRecord::MultiparameterAssignmentErrors.new(errors)
    assert_same errors, multiparameter_error.errors
  end

  def test_sql_warning_stores_metadata
    pool = Object.new
    warning = ActiveRecord::SQLWarning.new("warning", "01000", "WARNING", "SELECT 1", pool)

    assert_equal "warning", warning.message
    assert_equal "01000", warning.code
    assert_equal "WARNING", warning.level
    assert_equal "SELECT 1", warning.sql
    assert_same pool, warning.connection_pool

    warning.sql = "SELECT 2"
    assert_equal "SELECT 2", warning.sql
  end

  def test_sole_record_exceeded_messages
    named_record = Struct.new(:name).new("Widget")

    assert_equal "Wanted only one Widget", ActiveRecord::SoleRecordExceeded.new(named_record).message
    assert_same named_record, ActiveRecord::SoleRecordExceeded.new(named_record).record
    assert_equal "Wanted only one record", ActiveRecord::SoleRecordExceeded.new.message
  end

  def test_stale_object_error_messages
    record_class = Class.new do
      def self.name
        "Widget"
      end
    end
    record = record_class.new

    detailed = ActiveRecord::StaleObjectError.new(record, "update")
    assert_equal "Attempted to update a stale object: Widget.", detailed.message
    assert_same record, detailed.record
    assert_equal "update", detailed.attempted_action

    generic = ActiveRecord::StaleObjectError.new
    assert_equal "Stale object error.", generic.message
    assert_nil generic.record
    assert_nil generic.attempted_action
  end

  def test_unknown_primary_key_messages
    model = Class.new do
      def self.table_name
        "widgets"
      end

      def self.to_s
        "Widget"
      end
    end

    error = ActiveRecord::UnknownPrimaryKey.new(model, "custom detail")
    assert_equal "Unknown primary key for table widgets in model Widget.\ncustom detail", error.message
    assert_same model, error.model

    without_description = ActiveRecord::UnknownPrimaryKey.new(model)
    assert_equal "Unknown primary key for table widgets in model Widget.", without_description.message
    assert_same model, without_description.model

    assert_equal "Unknown primary key.", ActiveRecord::UnknownPrimaryKey.new.message
  end

  def test_eager_load_polymorphic_error_message_without_reflection
    error = ActiveRecord::EagerLoadPolymorphicError.new

    assert_equal "Eager load polymorphic error.", error.message
  end

  def test_can_be_instantiated_with_no_args
    base = ActiveRecord::ActiveRecordError
    error_klasses = ObjectSpace.each_object(Class).select { |klass| klass < base }

    expected_to_be_initializable_with_no_args = error_klasses - [
      ActiveRecord::AmbiguousSourceReflectionForThroughAssociation,
      ActiveRecord::DeprecatedAssociationError
    ]
    assert_nothing_raised do
      expected_to_be_initializable_with_no_args.each do |error_klass|
        error_klass.new.inspect
      rescue ArgumentError
        raise "Instance of #{error_klass} can't be initialized with no arguments"
      end
    end
  end
end
