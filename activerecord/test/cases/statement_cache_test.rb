# frozen_string_literal: true

require "cases/helper"
require "models/book"
require "models/liquid"
require "models/molecule"
require "models/numeric_data"
require "models/electron"
require "models/clothing_item"

module ActiveRecord
  class StatementCacheTest < ActiveRecord::TestCase
    def setup
      @connection = ActiveRecord::Base.lease_connection
    end

    def test_statement_cache
      Book.create(name: "my book")
      Book.create(name: "my other book")

      cache = StatementCache.create(ClothingItem.lease_connection) do |params|
        Book.where(name: params.bind)
      end

      b = cache.execute([ "my book" ], ClothingItem.lease_connection)
      assert_equal "my book", b[0].name
      b = cache.execute([ "my other book" ], ClothingItem.lease_connection)
      assert_equal "my other book", b[0].name
    end

    def test_statement_cache_id
      b1 = Book.create(name: "my book")
      b2 = Book.create(name: "my other book")

      cache = StatementCache.create(ClothingItem.lease_connection) do |params|
        Book.where(id: params.bind)
      end

      b = cache.execute([ b1.id ], ClothingItem.lease_connection)
      assert_equal b1.name, b[0].name
      b = cache.execute([ b2.id ], ClothingItem.lease_connection)
      assert_equal b2.name, b[0].name
    end

    def test_find_or_create_by
      Book.create(name: "my book")

      a = Book.find_or_create_by(name: "my book")
      b = Book.find_or_create_by(name: "my other book")

      assert_equal("my book", a.name)
      assert_equal("my other book", b.name)
    end

    def test_statement_cache_with_simple_statement
      cache = ActiveRecord::StatementCache.create(ClothingItem.lease_connection) do |params|
        Book.where(name: "my book").where("author_id > 3")
      end

      Book.create(name: "my book", author_id: 4)

      books = cache.execute([], ClothingItem.lease_connection)
      assert_equal "my book", books[0].name
    end

    def test_statement_cache_with_complex_statement
      cache = ActiveRecord::StatementCache.create(ClothingItem.lease_connection) do |params|
        Liquid.joins(molecules: :electrons).where("molecules.name" => "dioxane", "electrons.name" => "lepton")
      end

      salty = Liquid.create(name: "salty")
      molecule = salty.molecules.create(name: "dioxane")
      molecule.electrons.create(name: "lepton")

      liquids = cache.execute([], ClothingItem.lease_connection)
      assert_equal "salty", liquids[0].name
    end

    def test_statement_cache_with_strictly_cast_attribute
      row = NumericData.create(temperature: 1.5)
      assert_equal row, NumericData.find_by(temperature: 1.5)
    end

    def test_statement_cache_values_differ
      cache = ActiveRecord::StatementCache.create(ClothingItem.lease_connection) do |params|
        Book.where(name: "my book")
      end

      3.times do
        Book.create(name: "my book")
      end

      first_books = cache.execute([], ClothingItem.lease_connection)

      3.times do
        Book.create(name: "my book")
      end

      additional_books = cache.execute([], ClothingItem.lease_connection)
      assert_not_equal first_books, additional_books
    end

    def test_partial_query_collector_add_binds
      collector = ActiveRecord::StatementCache.partial_query_collector
      binds = [1, 2, 3]

      assert_same collector, collector.add_binds(binds)

      parts, collected_binds = collector.value
      assert_equal binds, collected_binds
      assert_equal 5, parts.size
      assert_equal [ActiveRecord::StatementCache::Substitute, String, ActiveRecord::StatementCache::Substitute, String, ActiveRecord::StatementCache::Substitute], parts.map(&:class)
      assert_equal [", ", ", "], parts.select { |part| part.is_a?(String) }
    end

    def test_partial_query_collector_add_binds_with_proc
      collector = ActiveRecord::StatementCache.partial_query_collector
      binds = [1, 2]

      collector.add_binds(binds, ->(value) { value * 10 })

      parts, collected_binds = collector.value
      assert_equal [10, 20], collected_binds
      assert_equal 3, parts.size
    end

    def test_partial_query_quotes_plain_bind_values
      query = ActiveRecord::StatementCache.partial_query(["id = ", ActiveRecord::StatementCache::Substitute.new], retryable: false)

      assert_equal "id = 1", query.sql_for([1], ActiveRecord::Base.lease_connection)
    end

    def test_statement_cache_execute_uses_async_find_by_sql
      query_builder = Struct.new(:retryable) do
        def sql_for(bind_values, connection)
          "SELECT * FROM books WHERE id = #{bind_values.first}"
        end
      end.new(true)
      bind_map = Struct.new(:binds) do
        def bind(params)
          binds.replace(params)
        end
      end.new([])
      model = Class.new do
        class << self
          attr_accessor :calls

          def async_find_by_sql(sql, bind_values, preparable:, allow_retry:, &block)
            self.calls = [sql, bind_values, preparable, allow_retry, block]
            :async_result
          end
        end
      end
      cache = ActiveRecord::StatementCache.new(query_builder, bind_map, model)
      callback = -> {}

      assert_equal :async_result, cache.execute([1], ActiveRecord::Base.lease_connection, async: true, &callback)
      assert_equal ["SELECT * FROM books WHERE id = 1", [1], true, true, callback], model.calls
    end

    def test_statement_cache_execute_returns_empty_result_on_range_error
      query_builder = Struct.new(:retryable) do
        def sql_for(bind_values, connection)
          raise ::RangeError
        end
      end.new(false)
      bind_map = Struct.new(:binds) do
        def bind(params)
          binds.replace(params)
        end
      end.new([])
      model = Class.new
      cache = ActiveRecord::StatementCache.new(query_builder, bind_map, model)

      assert_equal [], cache.execute([1], ActiveRecord::Base.lease_connection)

      promise_singleton = ActiveRecord::Promise.singleton_class
      had_wrap = promise_singleton.method_defined?(:wrap)
      original_wrap = ActiveRecord::Promise.method(:wrap) if had_wrap
      promise_singleton.define_method(:wrap) { |value| value }
      assert_equal [], cache.execute([1], ActiveRecord::Base.lease_connection, async: true)
    ensure
      if defined?(promise_singleton) && had_wrap
        promise_singleton.define_method(:wrap, original_wrap)
      elsif defined?(promise_singleton)
        promise_singleton.remove_method(:wrap)
      end
    end

    def test_statement_cache_unsupported_value_predicate
      assert ActiveRecord::StatementCache.unsupported_value?(nil)
      assert ActiveRecord::StatementCache.unsupported_value?([1])
      assert ActiveRecord::StatementCache.unsupported_value?(1..2)
      assert ActiveRecord::StatementCache.unsupported_value?({ id: 1 })
      assert ActiveRecord::StatementCache.unsupported_value?(Book.where(id: 1))
      assert ActiveRecord::StatementCache.unsupported_value?(Book.new)
      assert_not ActiveRecord::StatementCache.unsupported_value?(1)
    end

    def test_unprepared_statements_dont_share_a_cache_with_prepared_statements
      Book.create(name: "my book")
      Book.create(name: "my other book")

      book = Book.find_by(name: "my book")
      other_book = Book.lease_connection.unprepared_statement do
        Book.find_by(name: "my other book")
      end

      assert_not_equal book, other_book
    end

    def test_find_by_does_not_use_statement_cache_if_table_name_is_changed
      liquid = Liquid.create(name: "salty")

      Liquid.find_by(name: liquid.name) # warming the statement cache.

      # changing the table name should change the query that is not cached.
      Liquid.table_name = :birds
      assert_nil Liquid.find_by(name: liquid.name)
    ensure
      Liquid.table_name = :liquid
    end

    def test_find_does_not_use_statement_cache_if_table_name_is_changed
      liquid = Liquid.create(name: "salty")

      Liquid.find(liquid.id) # warming the statement cache.

      # changing the table name should change the query that is not cached.
      Liquid.table_name = :birds
      assert_raise ActiveRecord::RecordNotFound do
        Liquid.find(liquid.id)
      end
    ensure
      Liquid.table_name = :liquid
    end

    def test_find_association_does_not_use_statement_cache_if_table_name_is_changed
      salty = Liquid.create(name: "salty")
      molecule = salty.molecules.create(name: "dioxane")

      assert_equal salty, molecule.liquid

      Liquid.table_name = :birds

      assert_nil molecule.reload_liquid
    ensure
      Liquid.table_name = :liquid
    end
  end
end
