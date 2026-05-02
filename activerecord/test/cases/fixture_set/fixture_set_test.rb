# frozen_string_literal: true

require "cases/helper"
require "tmpdir"

module ActiveRecord
  class FixtureSetPublicContractTest < ActiveRecord::TestCase
    FakeConfig = Struct.new(:pluralize_table_names, :table_name_prefix, :table_name_suffix, :connection_pool, keyword_init: true)
    FoundFixture = Struct.new(:record) do
      def find
        record
      end
    end
    MissingClassFixture = Struct.new(:record) do
      def find
        raise ActiveRecord::FixtureClassNotFound
      end
    end

    class FakeConnection
      attr_reader :inserted_rows, :inserted_tables, :reset_tables

      def insert_fixtures_set(rows, tables)
        @inserted_rows = rows
        @inserted_tables = tables
      end

      def reset_column_sequences!(tables)
        @reset_tables = tables
      end
    end

    class FakeConnectionPool
      attr_reader :connection

      def initialize(connection = FakeConnection.new)
        @connection = connection
      end

      def with_connection
        yield connection
      end
    end

    def setup
      @previous_loaded_fixtures = FixtureSet.all_loaded_fixtures
      FixtureSet.all_loaded_fixtures = {}
      FixtureSet.reset_cache
    end

    def teardown
      FixtureSet.all_loaded_fixtures = @previous_loaded_fixtures
      FixtureSet.reset_cache
    end

    def test_default_names_identifiers_and_context_class
      assert_equal "Book", FixtureSet.default_fixture_model_name("books")
      assert_equal "Books", FixtureSet.default_fixture_model_name("books", fake_config(pluralize_table_names: false))
      assert_equal :prefix_admin_users_suffix, FixtureSet.default_fixture_table_name("admin/users", fake_config)

      integer_id = FixtureSet.identify("book")
      assert_kind_of Integer, integer_id
      assert_operator integer_id, :<, FixtureSet::MAX_ID
      assert_match(/\A[0-9a-f-]{36}\z/, FixtureSet.identify("book", :uuid))
      assert_equal ["tenant_id", "id"], FixtureSet.composite_identify("book", ["tenant_id", "id"]).keys
      assert_same FixtureSet.context_class, FixtureSet.context_class
    end

    def test_cache_helpers_and_create_fixtures_cache_hit
      connection_pool = Object.new
      fixture_set = Object.new

      assert_equal({}, FixtureSet.cache_for_connection_pool(connection_pool))
      assert_nil FixtureSet.fixture_is_cached?(connection_pool, "books")

      FixtureSet.cache_fixtures(connection_pool, "books" => fixture_set)

      assert_same fixture_set, FixtureSet.fixture_is_cached?(connection_pool, "books")
      assert_equal [fixture_set], FixtureSet.cached_fixtures(connection_pool)
      assert_equal [fixture_set], FixtureSet.cached_fixtures(connection_pool, ["books"])
      assert_equal [fixture_set], FixtureSet.create_fixtures("unused", ["books"], {}, fake_config(connection_pool: connection_pool))

      FixtureSet.reset_cache
      assert_equal({}, FixtureSet.cache_for_connection_pool(connection_pool))
    end

    def test_create_fixtures_reads_inserts_caches_and_resets_sequences
      connection = FakeConnection.new
      connection_pool = FakeConnectionPool.new(connection)

      Dir.mktmpdir do |dir|
        File.write(File.join(dir, "fixture_contract_widgets.yml"), <<~YAML)
          one:
            title: Widget One
        YAML

        fixture_set = FixtureSet.create_fixtures(dir, "fixture_contract_widgets", {}, fake_config(connection_pool: connection_pool)).first

        assert_instance_of FixtureSet, fixture_set
        assert_same fixture_set, FixtureSet.fixture_is_cached?(connection_pool, "fixture_contract_widgets")
        assert_equal [:fixture_contract_widgets], connection.inserted_tables
        assert_equal({ "title" => "Widget One" }, connection.inserted_rows[:fixture_contract_widgets].first)
        assert_equal [[:fixture_contract_widgets]], connection.reset_tables
        assert_same fixture_set, FixtureSet.all_loaded_fixtures["fixture_contract_widgets"]
      end
    end

    def test_instantiate_fixture_helpers
      object = Object.new
      fixture_set = {
        "found" => FoundFixture.new("record"),
        "missing" => MissingClassFixture.new(nil),
      }

      FixtureSet.instantiate_fixtures(object, fixture_set)

      assert_equal "record", object.instance_variable_get(:@found)
      assert_nil object.instance_variable_get(:@missing)

      FixtureSet.all_loaded_fixtures = { "books" => { "found_again" => FoundFixture.new("record again") } }
      FixtureSet.instantiate_all_loaded_fixtures(object)

      assert_equal "record again", object.instance_variable_get(:@found_again)
    end

    def test_instance_index_assignment_iteration_size_and_table_rows
      Dir.mktmpdir do |dir|
        path = File.join(dir, "widgets")
        File.write("#{path}.yml", <<~YAML)
          _fixture:
            ignore:
              - ignored_book
              - DEFAULTS
          one:
            title: Book One
          ignored_book:
            title: Ignored
          DEFAULTS:
            title: Defaults
        YAML

        fixture_set = FixtureSet.new(nil, "widgets", nil, path, fake_config)

        assert_equal :prefix_widgets_suffix, fixture_set.table_name
        assert_equal 3, fixture_set.size
        assert_equal "Book One", fixture_set["one"]["title"]

        fixture_set["two"] = Fixture.new({ "title" => "Book Two" }, nil)

        assert_equal %w[one ignored_book DEFAULTS two], fixture_set.each.map(&:first)
        assert_equal "Book Two", fixture_set["two"]["title"]
        assert_equal({ "title" => "Book One" }, fixture_set.table_rows[:prefix_widgets_suffix].first)
        assert_nil fixture_set["ignored_book"]
        assert_nil fixture_set["DEFAULTS"]
      end
    end

    private
      def fake_config(pluralize_table_names: true, connection_pool: Object.new)
        FakeConfig.new(
          pluralize_table_names: pluralize_table_names,
          table_name_prefix: "prefix_",
          table_name_suffix: "_suffix",
          connection_pool: connection_pool,
        )
      end
  end
end
