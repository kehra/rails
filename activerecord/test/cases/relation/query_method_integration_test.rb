# frozen_string_literal: true

require "cases/helper"
require "models/author"
require "models/post"

module ActiveRecord
  class QueryMethodIntegrationTest < ActiveRecord::TestCase
    fixtures :authors, :posts

    test "where chains with order and limit accumulate without mutating the source relation" do
      author = authors(:david)
      post = posts(:welcome)
      source = Post.where(author_id: author.id)
      source_sql = source.to_sql

      relation = source.where(title: post.title).order(id: :desc).limit(1)

      assert_equal [post], relation.to_a
      assert_equal source_sql, source.to_sql
      assert_equal Post.where(author_id: author.id).order(id: :asc).pluck(:id), source.order(id: :asc).pluck(:id)
      assert_equal 1, relation.limit_value
      assert_equal [post.id], relation.ids
    end

    test "rewhere replaces matching predicates and unscope removes where clauses without mutating the source relation" do
      author = authors(:david)
      post = posts(:welcome)
      source = Post.where(author_id: author.id).where(title: "missing title")
      source_sql = source.to_sql

      replaced = source.rewhere(title: post.title)
      without_title = replaced.unscope(where: :title)
      without_where = replaced.unscope(:where)

      assert_equal [post], replaced.to_a
      assert_equal source_sql, source.to_sql
      assert_equal Post.where(author_id: author.id).order(:id).ids, without_title.order(:id).ids
      assert_equal Post.order(:id).ids, without_where.order(:id).ids
    end

    test "where not and or compose with order without dropping predicates" do
      author = authors(:david)
      post = posts(:welcome)
      negative = Post.where.not(author_id: author.id)
      positive = Post.where(title: post.title)
      relation = negative.or(positive).order(:id)

      expected = Post.all.to_a.select { |candidate| candidate.author_id != author.id || candidate.title == post.title }

      assert_equal expected.sort_by(&:id), relation.to_a
      assert_equal Post.where.not(author_id: author.id).order(:id).ids, negative.order(:id).ids
      assert_equal [post], positive.to_a
    end

    test "and combines compatible where and having clauses and rejects incompatible relations" do
      author = authors(:david)
      source = Post.where.not(author_id: nil).group(:author_id).having("COUNT(*) > 0")
      compatible = Post.where(author_id: author.id).group(:author_id).having("COUNT(*) >= 1")
      combined = source.and(compatible)

      assert_equal [author.id], combined.pluck(:author_id)
      assert_equal Post.where.not(author_id: nil).group(:author_id).having("COUNT(*) > 0").pluck(:author_id).sort, source.pluck(:author_id).sort

      error = assert_raises(ArgumentError) do
        source.and(Post.order(:id))
      end
      assert_match(/structurally compatible/, error.message)
    end

    test "or with none composes with a normal relation and preserves later where clauses" do
      author = authors(:david)
      post = posts(:welcome)
      empty = Post.none
      normal = Post.where(id: post.id)
      relation = empty.or(normal).where(author_id: author.id)

      assert_equal [post], relation.to_a
      assert_empty empty.to_a
      assert_equal [post], normal.to_a
    end

    test "where with subquery and merge keeps the subquery predicate" do
      author = authors(:david)
      post = posts(:welcome)
      subquery = Post.where(author_id: author.id).select(:id)
      relation = Post.where(id: subquery).merge(Post.where(title: post.title))

      assert_equal [post], relation.to_a
      assert_equal Post.where(author_id: author.id).order(:id).ids, subquery.reorder(:id).ids
      assert_match(/SELECT/i, relation.to_sql)
    end

    test "reselect replaces projection while preserving order" do
      source = Post.select(:id, :title).order(id: :desc)
      source_sql = source.to_sql
      relation = source.reselect(:id)
      record = relation.first

      assert_equal Post.order(id: :desc).first.id, record.id
      assert_raises(ActiveModel::MissingAttributeError) { record.title }
      assert_match(/ORDER BY/i, relation.to_sql)
      assert_equal source_sql, source.to_sql
    end

    test "distinct select with order returns ordered unique projected values" do
      relation = Post.select(:author_id).distinct.order(:author_id)

      assert_equal Post.order(:author_id).pluck(:author_id).uniq, relation.map(&:author_id)
      assert_match(/DISTINCT/i, relation.to_sql)
    end

    test "select with joins and where keeps joined predicate and protects missing attributes" do
      author = authors(:david)
      relation = Post.joins(:author).where("authors.id = ?", author.id).select(:id).order(:id)
      record = relation.first

      assert_equal Post.where(author_id: author.id).order(:id).first.id, record.id
      assert_raises(ActiveModel::MissingAttributeError) { record.title }
      assert_match(/JOIN/i, relation.to_sql)
    end

    test "pluck with select and distinct does not leak projection to later queries" do
      source = Post.select(:author_id).distinct
      source_sql = source.to_sql

      assert_equal Post.distinct.order(:author_id).pluck(:author_id), source.order(:author_id).pluck(:author_id)
      assert_equal source_sql, source.to_sql
      assert_equal Post.order(:id).pluck(:id), Post.order(:id).ids
    end

    test "ids preserves order and limit" do
      relation = Post.order(id: :desc).limit(2)

      assert_equal Post.order(id: :desc).limit(2).pluck(:id), relation.ids
      assert_equal 2, relation.limit_value
      assert_match(/ORDER BY/i, relation.to_sql)
    end
  end
end
