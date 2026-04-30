# frozen_string_literal: true

require "cases/helper"

module ActiveRecord
  class Migration
    class SchemaDefinitionsTest < ActiveRecord::TestCase
      attr_reader :connection

      def setup
        @connection = ActiveRecord::Base.lease_connection
      end

      def test_build_create_table_definition_with_block
        td = connection.build_create_table_definition :test do |t|
          t.column :foo, :string
        end

        id_column = td.columns.find { |col| col.name == "id" }
        assert_predicate id_column, :present?

        foo_column = td.columns.find { |col| col.name == "foo" }
        assert_predicate foo_column, :present?
      end

      def test_build_create_table_definition_without_block
        td = connection.build_create_table_definition(:test)

        id_column = td.columns.find { |col| col.name == "id" }
        assert_predicate id_column, :present?
      end

      def test_build_create_join_table_definition_with_block
        assert connection.table_exists?(:posts)
        assert connection.table_exists?(:comments)

        join_td = connection.build_create_join_table_definition(:posts, :comments) do |t|
          t.column :another_col, :string
        end

        assert_equal :comments_posts, join_td.name
        assert_equal ["another_col", "comment_id", "post_id"], join_td.columns.map(&:name).sort
      end

      def test_build_create_join_table_definition_without_block
        assert connection.table_exists?(:posts)
        assert connection.table_exists?(:comments)

        join_td = connection.build_create_join_table_definition(:posts, :comments)

        assert_equal :comments_posts, join_td.name
        assert_equal ["comment_id", "post_id"], join_td.columns.map(&:name).sort
      end

      def test_build_create_index_definition
        connection.create_table(:test) do |t|
          t.column :foo, :string
        end
        create_index = connection.build_create_index_definition(:test, :foo)

        assert_equal "index_test_on_foo", create_index.index.name
      ensure
        connection.drop_table(:test) if connection.table_exists?(:test)
      end

      def test_schema_definition_value_objects_and_table_definition_contracts
        index = ActiveRecord::ConnectionAdapters::IndexDefinition.new(
          "posts", "idx_posts_on_title", true, ["title"],
          lengths: { "title" => 10 }, orders: { "title" => :desc }, opclasses: { "title" => :text_ops },
          include: ["id"], nulls_not_distinct: true, valid: false
        )
        assert_not_predicate index, :valid?
        assert_equal({ length: 10, order: :desc, opclass: :text_ops }, index.column_options)
        assert index.defined_for?(["title"], name: "idx_posts_on_title", unique: true, valid: false, include: ["id"], nulls_not_distinct: true)
        assert index.defined_for?(nil, column: ["title"])
        assert_not index.defined_for?(["body"])

        column = ActiveRecord::ConnectionAdapters::ColumnDefinition.new("title", :string, { limit: 10, primary_key: false })
        assert_not_predicate column, :primary_key?
        column.limit = 20
        column.precision = 2
        column.scale = 1
        column.default = "hello"
        column.null = false
        column.collation = "binary"
        column.comment = "title comment"
        column.if_exists = true
        column.if_not_exists = true
        assert_equal [20, 2, 1, "hello", false, "binary", "title comment", true, true],
          [column.limit, column.precision, column.scale, column.default, column.null, column.collation, column.comment, column.if_exists, column.if_not_exists]
        assert_equal :datetime, column.aliased_types("timestamp", :fallback)
        assert_equal :fallback, column.aliased_types("string", :fallback)

        foreign_key = ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new("posts", "authors", name: "fk_posts_authors", column: [:author_id], primary_key: [:id], on_delete: :cascade, on_update: :restrict, validate: false, deferrable: true)
        assert_equal "fk_posts_authors", foreign_key.name
        assert_equal [:author_id], foreign_key.column
        assert_equal [:id], foreign_key.primary_key
        assert_equal :cascade, foreign_key.on_delete
        assert_equal :restrict, foreign_key.on_update
        assert foreign_key.deferrable
        assert foreign_key.custom_primary_key?
        assert_not foreign_key.validate?
        assert foreign_key.defined_for?(to_table: "authors", validate: false, column: :author_id)
        assert_not foreign_key.defined_for?(to_table: "comments")
        assert_includes [true, false], foreign_key.export_name_on_schema_dump?
        assert_nil ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new("posts", "authors", {}).export_name_on_schema_dump?

        check = ActiveRecord::ConnectionAdapters::CheckConstraintDefinition.new("posts", "price > 0", name: "chk_posts_price", validate: false)
        assert_equal "chk_posts_price", check.name
        assert_not check.validate?
        assert check.defined_for?(name: "chk_posts_price", expression: "price > 0", validate: false)
        assert_not check.defined_for?(name: "different")
        optioned_check = ActiveRecord::ConnectionAdapters::CheckConstraintDefinition.new("posts", "price > 0", name: "chk_posts_price", validate: false, deferrable: true)
        assert_not optioned_check.defined_for?(name: "chk_posts_price", expression: "price > 0", validate: false, deferrable: false)
        assert_includes [true, false], check.export_name_on_schema_dump?
        assert_nil ActiveRecord::ConnectionAdapters::CheckConstraintDefinition.new("posts", "price > 0", {}).export_name_on_schema_dump?

        fake_connection = Class.new do
          attr_reader :foreign_key_calls, :check_constraint_calls
          def initialize
            @foreign_key_calls = []
            @check_constraint_calls = []
          end
          def valid_column_definition_options = ActiveRecord::ConnectionAdapters::ColumnDefinition::OPTION_NAMES + [:index, :_uses_legacy_reference_index_name, :_skip_validate_options]
          def supports_datetime_with_precision? = true
          def foreign_key_options(from, to, options)
            @foreign_key_calls << [from, to, options]
            options.reverse_merge(name: "fk_#{from}_#{to}", column: "#{to.to_s.singularize}_id", primary_key: "id")
          end
          def check_constraint_options(table, expression, options)
            @check_constraint_calls << [table, expression, options]
            options.reverse_merge(name: "chk_#{table}")
          end
        end.new

        table = ActiveRecord::ConnectionAdapters::TableDefinition.new(fake_connection, "schema_definition_posts")
        table.set_primary_key("schema_definition_posts", { type: :bigint, default: nil }, nil)
        assert table["id"].primary_key?
        assert_equal :bigint, table["id"].type
        table.column :title, :string, index: { name: "idx_schema_definition_posts_on_title" }
        table.column :body, nil
        table.virtual :search_vector
        table.timestamps
        precision_table = ActiveRecord::ConnectionAdapters::TableDefinition.new(fake_connection, "schema_definition_precision_posts")
        precision_table.timestamps precision: 3
        assert_equal 3, precision_table["created_at"].precision
        table.references :author, polymorphic: { default: "Author" }, index: true, if_not_exists: true
        table.foreign_key :authors, column: :author_id
        table.check_constraint "length(title) > 0"
        assert_equal ["id", "title", "body", "search_vector", "created_at", "updated_at", "author_type", "author_id"], table.columns.map(&:name)
        assert_equal "title", table["title"].name
        assert_equal 2, table.indexes.size
        assert_equal 1, table.foreign_keys.size
        assert_equal 1, table.check_constraints.size
        table.remove_column :search_vector
        assert_nil table["search_vector"]

        duplicate_error = assert_raises(ArgumentError) { table.column :title, :string }
        assert_match(/already defined column/, duplicate_error.message)
        pk_error = assert_raises(ArgumentError) { table.primary_key :id }
        assert_match(/redefine the primary key/, pk_error.message)

        composite = ActiveRecord::ConnectionAdapters::TableDefinition.new(fake_connection, "schema_definition_composites")
        composite.set_primary_key("schema_definition_composites", true, ["tenant_id", "id"])
        assert_equal ["tenant_id", "id"], composite.primary_keys.name

        assert_raises(ArgumentError) { ActiveRecord::ConnectionAdapters::ReferenceDefinition.new(:imageable, polymorphic: true, foreign_key: true) }
      end

      def test_schema_definition_reference_and_table_command_contracts
        recorder = Class.new do
          attr_reader :calls
          def initialize = @calls = []
          def method_missing(name, *args, **options)
            @calls << [name, args, options]
            name.to_s.end_with?("?") ? true : :ok
          end
          def respond_to_missing?(*); true; end
        end.new

        reference = ActiveRecord::ConnectionAdapters::ReferenceDefinition.new(:author, index: { unique: true }, foreign_key: { to_table: :people }, type: :integer, if_exists: true)
        reference.add(:posts, recorder)
        ActiveRecord::ConnectionAdapters::ReferenceDefinition.new(:category, index: false, foreign_key: false).add(:posts, recorder)
        ActiveRecord::ConnectionAdapters::ReferenceDefinition.new(:legacy, polymorphic: true, index: true, _uses_legacy_reference_index_name: true).add(:posts, recorder)
        old_pluralize_table_names = ActiveRecord::Base.pluralize_table_names
        ActiveRecord::Base.pluralize_table_names = false
        ActiveRecord::ConnectionAdapters::ReferenceDefinition.new(:person, index: false, foreign_key: true).add(:posts, recorder)
        ActiveRecord::Base.pluralize_table_names = old_pluralize_table_names
        assert_includes recorder.calls, [:add_column, [:posts, "author_id", :integer], { if_exists: true }]
        assert_includes recorder.calls, [:add_index, [:posts, ["author_id"]], { unique: true, if_exists: true }]
        assert_includes recorder.calls, [:add_foreign_key, [:posts, :people], { to_table: :people, column: "author_id", if_exists: true }]

        table = ActiveRecord::ConnectionAdapters::Table.new(:posts, recorder)
        table.column(:title, :string, index: { unique: true })
        table.column(:subtitle, :string, index: true)
        table.column(:summary, :string)
        assert table.column_exists?(:title, :string)
        table.index(:title)
        assert table.index_exists?(:title)
        table.rename_index(:old_idx, :new_idx)
        table.timestamps(null: false)
        table.change(:title, :text)
        table.change_default(:title, from: nil, to: "hello")
        table.change_null(:title, false, "")
        table.remove(:old_title, :legacy_title)
        table.remove_index(:title)
        table.remove_timestamps
        table.rename(:title, :headline)
        table.references(:editor, foreign_key: true)
        table.remove_references(:editor, polymorphic: true)
        table.foreign_key(:authors)
        table.remove_foreign_key(:authors)
        assert table.foreign_key_exists?(:authors)
        table.check_constraint("price > 0", name: "chk_price")
        table.remove_check_constraint(name: "chk_price")
        assert table.check_constraint_exists?(name: "chk_price")

        assert_includes recorder.calls, [:add_column, [:posts, :title, :string], {}]
        assert_includes recorder.calls, [:add_index, [:posts, :title], { unique: true }]
        assert_includes recorder.calls, [:add_timestamps, [:posts], { null: false }]
        assert_includes recorder.calls, [:rename_column, [:posts, :title, :headline], {}]

        if_exists_error = assert_raises(ArgumentError) { table.column(:body, :text, if_exists: true) }
        assert_match(/Option if_exists will be ignored/, if_exists_error.message)
        if_not_exists_error = assert_raises(ArgumentError) { table.index(:body, if_not_exists: true) }
        assert_match(/Option if_not_exists will be ignored/, if_not_exists_error.message)
      end

      def test_schema_statements_abstract_defaults_and_helper_contracts
        connection_class = Class.new do
          include ActiveRecord::ConnectionAdapters::SchemaStatements

          attr_reader :executed_sql, :schema_cache

          def initialize
            @executed_sql = []
            @schema_cache = Class.new do
              attr_reader :cleared
              def initialize = @cleared = []
              def clear_data_source_cache!(name) = @cleared << name
            end.new
          end

          def execute(sql)
            @executed_sql << sql
            sql
          end

          def query_values(sql)
            case sql
            when /BASE TABLE/ then ["posts"]
            when /VIEW/ then ["post_views"]
            else ["posts", "post_views"]
            end
          end

          def quote_table_name(name) = %Q("#{name}")
          def quote_column_name(name) = %Q("#{name}")
          def quote(value) = value.inspect
          def type_cast(value) = value
          def lookup_cast_type_from_column(_column) = ActiveModel::Type::Value.new
          def table_alias_length = 10
          def primary_keys(_table_name) = ["id"]
          def column_definitions(_table_name) = []
          def new_column_from_field(*) = nil
          def supports_indexes_in_create? = false
          def supports_comments? = false
          def supports_comments_in_create? = false
          def supports_datetime_with_precision? = true
          def supports_index_sort_order? = true
          def supports_foreign_keys? = false
          def foreign_keys_enabled? = true
          def supports_check_constraints? = false
          def supports_exclusion_constraints? = false
          def supports_unique_constraints? = false
          def supports_index_include? = false
          def supports_partial_index? = false
          def supports_nulls_not_distinct? = false
          def index_name_length = 64
          def allowed_index_name_length = 64
          def table_name_length = 64
          def options_include_default?(options) = options.key?(:default)
          def type_to_sql(type, **options) = [type.to_s, options[:limit]].compact.join("(").then { |sql| options[:limit] ? "#{sql})" : sql }
          def data_source_sql(name = nil, type: nil) = ["DATA SOURCES", name, type].compact.join(" ")
          def schema_creation = ActiveRecord::ConnectionAdapters::SchemaCreation.new(self)
          def column_exists?(table_name, column_name, *_args, **_options)
            table_name.to_s == "posts" && column_name.to_s == "existing"
          end
          def indexes(_table_name)
            [ActiveRecord::ConnectionAdapters::IndexDefinition.new("posts", "index_posts_on_title", false, ["title"])]
          end
        end

        connection = connection_class.new
        assert_equal({}, connection.native_database_types)
        assert_nil connection.table_options(:posts)
        assert_nil connection.table_comment(:posts)
        assert_equal "very_long_", connection.table_alias_for("very.long.table")
        assert_equal ["posts", "post_views"], connection.data_sources
        assert connection.data_source_exists?(:posts)
        assert_equal ["posts"], connection.tables
        assert connection.table_exists?(:posts)
        assert_equal ["post_views"], connection.views
        assert connection.view_exists?(:post_views)
        assert connection.index_exists?(:posts, :title)
        assert_equal "id", connection.primary_key(:posts)

        create_sql = connection.create_table(:schema_statement_posts, if_not_exists: true) { |t| t.string :title, index: true }
        assert_match(/CREATE TABLE IF NOT EXISTS/, create_sql)
        assert_includes connection.schema_cache.cleared, "schema_statement_posts"
        assert_includes connection.executed_sql.last, "CREATE INDEX IF NOT EXISTS"

        forced_sql = connection.create_table(:forced_schema_statement_posts, force: true) { |t| t.string :title }
        assert_match(/CREATE TABLE/, forced_sql)
        assert connection.executed_sql.any? { |sql| sql.include?(%Q(DROP TABLE IF EXISTS "forced_schema_statement_posts")) }
        force_error = assert_raises(ArgumentError) { connection.create_table(:bad_options, force: true, if_not_exists: true) }
        assert_match(/cannot be used simultaneously/, force_error.message)

        join_definition = connection.build_create_join_table_definition(:music_artists, :music_records)
        assert_equal :music_artists_records, join_definition.name
        connection.create_join_table(:authors, :posts)
        assert connection.executed_sql.any? { |sql| sql.include?("authors_posts") }
        connection.drop_join_table(:authors, :posts)
        assert connection.executed_sql.any? { |sql| sql.include?(%Q(DROP TABLE "authors_posts")) }

        add_definition = connection.build_add_column_definition(:posts, :created_at, :datetime)
        assert_equal 6, add_definition.adds.first.column.precision
        assert_nil connection.build_add_column_definition(:posts, :existing, :string, if_not_exists: true)
        connection.add_column(:posts, :body, :text)
        connection.add_columns(:posts, :summary, :subtitle, type: :string)
        connection.remove_column(:posts, :legacy)
        connection.remove_columns(:posts, :legacy_one, :legacy_two)
        empty_remove_error = assert_raises(ArgumentError) { connection.remove_columns(:posts) }
        assert_match(/at least one column/, empty_remove_error.message)
        assert_nil connection.remove_column(:posts, :missing, if_exists: true)

        assert_raises(NotImplementedError) { connection.change_column(:posts, :title, :text) }
        assert_raises(NotImplementedError) { connection.change_column_default(:posts, :title, "hello") }
        assert_raises(NotImplementedError) { connection.build_change_column_default_definition(:posts, :title, "hello") }
        assert_raises(NotImplementedError) { connection.change_column_null(:posts, :title, false) }
        assert_raises(NotImplementedError) { connection.rename_column(:posts, :title, :headline) }
      end

      def test_schema_statements_index_reference_constraint_and_migration_contracts
        connection_class = Class.new do
          include ActiveRecord::ConnectionAdapters::SchemaStatements

          attr_reader :executed_sql, :removed_columns, :pool

          def initialize
            @executed_sql = []
            @removed_columns = []
            schema_migration = Struct.new(:table_name) do
              def versions = ["20240101010101", "20240202020202"]
            end.new("schema_migrations")
            migration_context = Struct.new(:all_versions, :migration_versions) do
              def get_all_versions = all_versions
              def migrations = migration_versions.map { |version| Struct.new(:version).new(version) }
            end.new([20240101010101], [20230101010101, 20240101010101])
            @pool = Struct.new(:schema_migration, :migration_context).new(schema_migration, migration_context)
          end

          def execute(sql)
            @executed_sql << sql
            sql
          end

          def quote(value) = value.inspect
          def quote_table_name(name) = %Q("#{name}")
          def quote_column_name(name) = %Q("#{name}")
          def options_include_default?(options) = options.key?(:default)
          def type_to_sql(type, **options) = [type.to_s, options[:limit]].compact.join("(").then { |sql| options[:limit] ? "#{sql})" : sql }
          def supports_index_sort_order? = true
          def supports_foreign_keys? = true
          def foreign_keys_enabled? = true
          def supports_check_constraints? = true
          def supports_indexes_in_create? = false
          def supports_datetime_with_precision? = true
          def supports_partial_index? = true
          def supports_index_include? = false
          def supports_nulls_not_distinct? = false
          def supports_exclusion_constraints? = false
          def supports_unique_constraints? = false
          def index_name_length = 64
          def allowed_index_name_length = 64
          def table_name_length = 64
          def schema_creation = ActiveRecord::ConnectionAdapters::SchemaCreation.new(self)
          def data_source_sql(name = nil, type: nil) = ["DATA SOURCES", name, type].compact.join(" ")
          def query_values(_sql) = []
          def columns(_table_name) = []
          def indexes(_table_name)
            [
              ActiveRecord::ConnectionAdapters::IndexDefinition.new("posts", "index_posts_on_title", false, ["title"]),
              ActiveRecord::ConnectionAdapters::IndexDefinition.new("posts", "custom_posts_idx", true, ["author_id"])
            ]
          end
          def foreign_keys(_table_name)
            [
              ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new("posts", "authors", name: "fk_posts_authors", column: "author_id", primary_key: "id"),
              ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.new("posts", "authors", name: "fk_posts_editor", column: "editor_id", primary_key: "id")
            ]
          end
          def check_constraints(_table_name)
            [ActiveRecord::ConnectionAdapters::CheckConstraintDefinition.new("posts", "price > 0", name: "chk_posts_price")]
          end
          def remove_column(table_name, column_name, **options)
            @removed_columns << [table_name, column_name, options]
          end
        end

        connection = connection_class.new
        connection.add_index(:posts, :title, name: "idx_posts_title", unique: true, where: "title IS NOT NULL")
        assert connection.executed_sql.last.include?("CREATE UNIQUE INDEX")
        connection.remove_index(:posts, :title)
        assert connection.executed_sql.last.include?("DROP INDEX")
        assert_nil connection.remove_index(:posts, :missing, if_exists: true)
        connection.rename_index(:posts, :index_posts_on_title, :renamed_posts_title)
        assert connection.executed_sql.any? { |sql| sql.include?("renamed_posts_title") }
        assert connection.index_name_exists?(:posts, :custom_posts_idx)
        assert_equal "index_posts_on_title", connection.index_name(:posts, column: :title, _uses_legacy_index_name: true)
        assert_equal :named_idx, connection.index_name(:posts, name: :named_idx)
        assert_raises(ArgumentError) { connection.index_name(:posts, {}) }

        connection.add_reference(:posts, :editor, index: { name: "idx_posts_editor" }, foreign_key: { to_table: :authors })
        assert connection.executed_sql.any? { |sql| sql.include?("idx_posts_editor") }
        connection.remove_reference(:posts, :editor, foreign_key: { to_table: :authors }, polymorphic: true, if_exists: true)
        assert connection.executed_sql.any? { |sql| sql.include?("DROP CONSTRAINT") && sql.include?("fk_posts_editor") }
        assert_includes connection.removed_columns, [:posts, "editor_id", { if_exists: true }]
        assert_includes connection.removed_columns, [:posts, "editor_type", { if_exists: true }]

        connection.add_foreign_key(:posts, :authors, if_not_exists: true)
        assert connection.executed_sql.none? { |sql| sql.include?("ADD CONSTRAINT") && sql.include?("fk_posts_authors") }
        assert connection.foreign_key_exists?(:posts, :authors)
        assert_equal "post_id", connection.foreign_key_column_for(:posts, :id)
        assert_raises(ArgumentError) { connection.foreign_key_options(:orders, :carts, primary_key: [:shop_id, :user_id], column: [:cart_shop_id]) }

        connection.remove_foreign_key(:posts, :authors)
        assert connection.executed_sql.any? { |sql| sql.include?("DROP CONSTRAINT") && sql.include?("fk_posts_authors") }
        assert_nil connection.remove_foreign_key(:posts, :missing, if_exists: true)

        connection.add_check_constraint(:posts, "price > 0", if_not_exists: true)
        assert connection.executed_sql.none? { |sql| sql.include?("ADD CONSTRAINT") && sql.include?("chk_posts_price") }
        assert connection.check_constraint_exists?(:posts, name: "chk_posts_price")
        assert_raises(ArgumentError) { connection.check_constraint_exists?(:posts) }
        connection.remove_check_constraint(:posts, name: "chk_posts_price")
        assert connection.executed_sql.any? { |sql| sql.include?("DROP CONSTRAINT") && sql.include?("chk_posts_price") }
        assert_nil connection.remove_check_constraint(:posts, name: "missing", if_exists: true)
        connection.remove_constraint(:posts, :generic_constraint)
        assert connection.executed_sql.last.include?("generic_constraint")

        assert_match(/INSERT INTO/, connection.dump_schema_versions)
        connection.assume_migrated_upto_version(20240202020202)
        assert connection.executed_sql.any? { |sql| sql.include?("20240202020202") }

        duplicate_connection = connection_class.new
        duplicate_connection.pool.migration_context.migration_versions.replace([20230101010101, 20230101010101])
        assert_raises(RuntimeError) { duplicate_connection.assume_migrated_upto_version(20240202020202) }
      end

      if current_adapter?(:Mysql2Adapter, :TrilogyAdapter)
        def test_build_create_index_definition_for_existing_index
          connection.create_table(:test) do |t|
            t.column :foo, :string
          end
          connection.add_index(:test, :foo)

          create_index = connection.build_create_index_definition(:test, :foo, if_not_exists: true)
          assert_nil create_index
        ensure
          connection.drop_table(:test) if connection.table_exists?(:test)
        end
      end

      unless current_adapter?(:SQLite3Adapter)
        def test_build_change_column_definition
          connection.create_table(:test) do |t|
            t.column :foo, :string
          end

          change_cd = connection.build_change_column_definition(:test, :foo, :integer)
          change_col = change_cd.column
          assert_equal "foo", change_col.name.to_s
        ensure
          connection.drop_table(:test) if connection.table_exists?(:test)
        end

        def test_build_change_column_default_definition
          connection.create_table(:test) do |t|
            t.column :foo, :string
          end

          change_default_cd = connection.build_change_column_default_definition(:test, :foo, "new")
          assert_equal "new", change_default_cd.default

          change_col = change_default_cd.column
          assert_equal "foo", change_col.name.to_s
        ensure
          connection.drop_table(:test) if connection.table_exists?(:test)
        end
      end
    end
  end
end
