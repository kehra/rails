# frozen_string_literal: true

require "cases/helper"

class SchemaDumperUnitTest < ActiveRecord::TestCase
  FakeMigrationContext = Struct.new(:current_version)
  FakePool = Struct.new(:migration_context)

  class FakeConnection
    attr_reader :pool
    attr_accessor :indexes_for_table, :check_constraints_for_table, :foreign_keys_for_table,
      :exclusion_constraints_for_table, :unique_constraints_for_table, :columns_for_table,
      :primary_key_for_table, :table_options_for_table, :supports_foreign_keys_value,
      :supports_check_constraints_value, :supports_exclusion_constraints_value,
      :supports_unique_constraints_value

    def initialize(version: nil)
      @pool = FakePool.new(FakeMigrationContext.new(version))
      @indexes_for_table = []
      @check_constraints_for_table = []
      @foreign_keys_for_table = []
      @exclusion_constraints_for_table = []
      @unique_constraints_for_table = []
      @columns_for_table = []
      @primary_key_for_table = "id"
      @table_options_for_table = {}
      @supports_foreign_keys_value = false
      @supports_check_constraints_value = false
      @supports_exclusion_constraints_value = false
      @supports_unique_constraints_value = false
    end

    def tables = ["widgets"]
    def columns(_table) = columns_for_table
    def primary_key(_table) = primary_key_for_table
    def table_options(_table) = table_options_for_table
    def valid_type?(type) = type != :invalid
    def indexes(_table) = indexes_for_table
    def check_constraints(_table) = check_constraints_for_table
    def foreign_keys(_table) = foreign_keys_for_table
    def exclusion_constraints(_table) = exclusion_constraints_for_table
    def unique_constraints(_table) = unique_constraints_for_table
    def supports_foreign_keys? = supports_foreign_keys_value
    def supports_check_constraints? = supports_check_constraints_value
    def supports_exclusion_constraints? = supports_exclusion_constraints_value
    def supports_unique_constraints? = supports_unique_constraints_value
    def supports_disabling_indexes? = true
    def default_index_type?(_index) = false
    def foreign_key_column_for(table, column) = "#{table.to_s.singularize}_#{column}"
  end

  FakeColumn = Struct.new(:name, :type, :sql_type, keyword_init: true)
  FakeNamedObject = Struct.new(:name, keyword_init: true)

  FakeIndex = Struct.new(
    :table, :columns, :name, :unique, :lengths, :orders, :opclasses, :where, :using,
    :include, :nulls_not_distinct, :type, :comment, :enabled, :disabled?, keyword_init: true
  )

  FakeCheck = Struct.new(:expression, :name, :validate?, :export_name_on_schema_dump?, keyword_init: true)

  FakeForeignKey = Struct.new(
    :from_table, :to_table, :column, :primary_key, :name, :on_update, :on_delete,
    :deferrable, :validate?, :export_name_on_schema_dump?, keyword_init: true
  ) do
    def custom_primary_key?
      primary_key != "id"
    end
  end

  def build_dumper(connection = FakeConnection.new, **options)
    ActiveRecord::SchemaDumper.send(:new, connection, options)
  end

  def test_formatted_version_and_define_params
    timestamped = build_dumper(FakeConnection.new(version: 20240102030405))
    assert_equal "2024_01_02_030405", timestamped.send(:formatted_version)
    assert_equal "version: 2024_01_02_030405", timestamped.send(:define_params)

    unversioned = build_dumper(FakeConnection.new(version: nil))
    assert_equal "", unversioned.send(:define_params)
  end

  def test_remove_prefix_and_suffix_only_when_options_are_present
    dumper = build_dumper(FakeConnection.new, table_name_prefix: "pre_", table_name_suffix: "_suf")

    assert_equal "widgets", dumper.send(:remove_prefix_and_suffix, "pre_widgets_suf")

    no_options = build_dumper(FakeConnection.new)
    assert_equal "pre_widgets_suf", no_options.send(:remove_prefix_and_suffix, "pre_widgets_suf")
  end

  def test_ignored_uses_strings_and_regexps_after_prefix_suffix_removal
    original_ignore_tables = ActiveRecord::SchemaDumper.ignore_tables
    ActiveRecord::SchemaDumper.ignore_tables = ["widgets", /legacy_/]
    dumper = build_dumper(FakeConnection.new, table_name_prefix: "pre_", table_name_suffix: "_suf")

    assert dumper.send(:ignored?, "pre_widgets_suf")
    assert dumper.send(:ignored?, "pre_legacy_events_suf")
    assert_not dumper.send(:ignored?, "pre_posts_suf")
  ensure
    ActiveRecord::SchemaDumper.ignore_tables = original_ignore_tables
  end

  def test_index_parts_dump_all_optional_attributes
    index = FakeIndex.new(
      table: "widgets", columns: ["name"], name: "idx_widgets_on_name", unique: true,
      lengths: { "name" => 10 }, orders: { "name" => :desc }, opclasses: { "name" => :text_pattern_ops },
      where: "name IS NOT NULL", using: :btree, include: ["id"], nulls_not_distinct: true,
      type: :fulltext, comment: "search", enabled: false, disabled?: true
    )

    parts = build_dumper.send(:index_parts, index)

    assert_includes parts, '["name"]'
    assert_includes parts, 'name: "idx_widgets_on_name"'
    assert_includes parts, "unique: true"
    assert_includes parts, 'length: { name: 10 }'
    assert_includes parts, 'order: { name: :desc }'
    assert_includes parts, 'opclass: { name: :text_pattern_ops }'
    assert_includes parts, 'where: "name IS NOT NULL"'
    assert_includes parts, 'using: :btree'
    assert_includes parts, 'include: ["id"]'
    assert_includes parts, 'nulls_not_distinct: true'
    assert_includes parts, 'type: :fulltext'
    assert_includes parts, 'comment: "search"'
    assert_includes parts, 'enabled: false'
  end

  def test_check_constraints_in_create_splits_valid_and_invalid_constraints
    connection = FakeConnection.new
    connection.check_constraints_for_table = [
      FakeCheck.new(expression: "price > 0", name: "price_check", validate?: true, export_name_on_schema_dump?: true),
      FakeCheck.new(expression: "quantity > 0", name: "quantity_check", validate?: false, export_name_on_schema_dump?: true)
    ]
    stream = StringIO.new

    remaining = build_dumper(connection).send(:check_constraints_in_create, "widgets", stream)

    assert_includes stream.string, 't.check_constraint "price > 0", name: "price_check"'
    assert_includes remaining.string, 'add_check_constraint "widgets", "quantity > 0", name: "quantity_check", validate: false'
  end

  def test_indexes_dump_legacy_add_index_statements
    connection = FakeConnection.new
    connection.indexes_for_table = [
      FakeIndex.new(table: "pre_widgets_suf", columns: ["name"], name: "idx_widgets_on_name", unique: false, disabled?: false)
    ]
    stream = StringIO.new

    build_dumper(connection, table_name_prefix: "pre_", table_name_suffix: "_suf").send(:indexes, "pre_widgets_suf", stream)

    assert_includes stream.string, 'add_index "widgets", ["name"], name: "idx_widgets_on_name"'
  end

  def test_indexes_in_create_omits_indexes_backing_exclusion_and_unique_constraints
    connection = FakeConnection.new
    connection.supports_exclusion_constraints_value = true
    connection.supports_unique_constraints_value = true
    connection.indexes_for_table = [
      FakeIndex.new(table: "widgets", columns: ["kept"], name: "idx_kept", unique: false, disabled?: false),
      FakeIndex.new(table: "widgets", columns: ["excluded"], name: "idx_excluded", unique: false, disabled?: false),
      FakeIndex.new(table: "widgets", columns: ["unique"], name: "idx_unique", unique: false, disabled?: false)
    ]
    connection.exclusion_constraints_for_table = [FakeNamedObject.new(name: "idx_excluded")]
    connection.unique_constraints_for_table = [FakeNamedObject.new(name: "idx_unique")]
    stream = StringIO.new

    build_dumper(connection).send(:indexes_in_create, "widgets", stream)

    assert_includes stream.string, 't.index ["kept"], name: "idx_kept"'
    assert_not_includes stream.string, "idx_excluded"
    assert_not_includes stream.string, "idx_unique"
  end

  def test_table_dumps_table_options_custom_primary_key_and_remaining_constraints
    connection = FakeConnection.new
    connection.columns_for_table = [
      FakeColumn.new(name: "uuid", type: :uuid, sql_type: "uuid"),
      FakeColumn.new(name: "payload", type: :json, sql_type: "json")
    ]
    connection.primary_key_for_table = "uuid"
    connection.table_options_for_table = { options: "WITHOUT ROWID" }
    connection.supports_check_constraints_value = true
    connection.check_constraints_for_table = [
      FakeCheck.new(expression: "json_valid(payload)", name: "payload_check", validate?: false, export_name_on_schema_dump?: true)
    ]
    dumper = build_dumper(connection)
    dumper.define_singleton_method(:column_spec_for_primary_key) { |_column| { id: :uuid, default: "gen_random_uuid()", limit: 16 } }
    dumper.define_singleton_method(:column_spec) { |_column| ["jsonb", {}] }
    stream = StringIO.new

    dumper.send(:table, "widgets", stream)

    output = stream.string
    assert_includes output, 'create_table "widgets", primary_key: "uuid", id: { type: uuid, default: gen_random_uuid(), limit: 16 }, options: "WITHOUT ROWID"'
    assert_includes output, 't.column "payload", "jsonb"'
    assert_includes output, 'add_check_constraint "widgets", "json_valid(payload)", name: "payload_check", validate: false'
  end

  def test_table_reports_unknown_column_type_errors
    connection = FakeConnection.new
    connection.columns_for_table = [FakeColumn.new(name: "payload", type: :invalid, sql_type: "mystery")]
    connection.primary_key_for_table = nil
    stream = StringIO.new

    build_dumper(connection).send(:table, "widgets", stream)

    assert_includes stream.string, '# Could not dump table "widgets" because of following StandardError'
    assert_includes stream.string, "Unknown type 'mystery' for column 'payload'"
  end

  def test_table_skips_optional_constraint_sections_when_unsupported
    connection = FakeConnection.new
    connection.columns_for_table = [FakeColumn.new(name: "name", type: :string, sql_type: "varchar")]
    connection.primary_key_for_table = nil
    dumper = build_dumper(connection)
    dumper.define_singleton_method(:column_spec) { |_column| [:string, {}] }
    stream = StringIO.new

    dumper.send(:table, "widgets", stream)

    assert_includes stream.string, 'create_table "widgets", id: false'
  end

  def test_table_invokes_supported_exclusion_and_unique_constraint_sections
    connection = FakeConnection.new
    connection.columns_for_table = [FakeColumn.new(name: "id", type: :integer, sql_type: "integer")]
    connection.primary_key_for_table = "id"
    connection.supports_exclusion_constraints_value = true
    connection.supports_unique_constraints_value = true
    dumper = build_dumper(connection)
    dumper.define_singleton_method(:column_spec_for_primary_key) { |_column| {} }
    dumper.define_singleton_method(:exclusion_constraints_in_create) { |_table, stream| stream.puts '    t.exclusion_constraint "room WITH ="' }
    dumper.define_singleton_method(:unique_constraints_in_create) { |_table, stream| stream.puts '    t.unique_constraint ["name"]' }
    stream = StringIO.new

    dumper.send(:table, "widgets", stream)

    assert_includes stream.string, 't.exclusion_constraint "room WITH ="'
    assert_includes stream.string, 't.unique_constraint ["name"]'
  end

  def test_indexes_noops_without_indexes
    stream = StringIO.new

    build_dumper(FakeConnection.new).send(:indexes, "widgets", stream)

    assert_equal "", stream.string
  end

  def test_check_parts_omits_internal_name
    check = FakeCheck.new(expression: "price > 0", name: "internal", validate?: true, export_name_on_schema_dump?: false)

    assert_equal ['"price > 0"'], build_dumper.send(:check_parts, check)
  end

  def test_tables_skips_foreign_key_dump_when_unsupported
    connection = FakeConnection.new
    stream = StringIO.new
    dumper = build_dumper(connection)
    dumper.define_singleton_method(:table) { |table, output| output.puts "table: #{table}" }

    dumper.send(:tables, stream)

    assert_equal "table: widgets\n", stream.string
  end

  def test_foreign_keys_dump_all_optional_attributes
    connection = FakeConnection.new
    connection.foreign_keys_for_table = [
      FakeForeignKey.new(
        from_table: "orders", to_table: "accounts", column: "account_uuid", primary_key: "uuid",
        name: "fk_orders_accounts", on_update: :cascade, on_delete: :nullify, deferrable: :deferred,
        validate?: false, export_name_on_schema_dump?: true
      )
    ]
    stream = StringIO.new

    build_dumper(connection).send(:foreign_keys, "orders", stream)

    output = stream.string
    assert_includes output, 'add_foreign_key "orders", "accounts"'
    assert_includes output, 'column: "account_uuid"'
    assert_includes output, 'primary_key: "uuid"'
    assert_includes output, 'name: "fk_orders_accounts"'
    assert_includes output, 'on_update: :cascade'
    assert_includes output, 'on_delete: :nullify'
    assert_includes output, 'deferrable: :deferred'
    assert_includes output, 'validate: false'
  end
end
