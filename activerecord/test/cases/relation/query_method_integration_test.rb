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
  end
end
