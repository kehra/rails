# frozen_string_literal: true

require "cases/helper"
require "models/author"
require "models/comment"
require "models/post"
require "models/tagging"

module ActiveRecord
  class QueryMethodIntegrationTest < ActiveRecord::TestCase
    fixtures :authors, :posts, :comments, :taggings

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

    test "joins with where and merge combines association scope predicates" do
      author = authors(:david)
      post = posts(:welcome)
      source = Post.joins(:author)
      source_sql = source.to_sql
      relation = source.where(title: post.title).merge(Author.where(id: author.id))

      assert_equal [post], relation.to_a
      assert_equal source_sql, source.to_sql
      assert_match(/JOIN/i, relation.to_sql)
    end

    test "left outer joins with where and distinct keeps rows missing the association" do
      relation = Post.left_outer_joins(:taggings).where("taggings.id IS NULL").distinct.order(:id)
      tagged_post_ids = Tagging.where(taggable_type: "Post").select(:taggable_id)
      expected = Post.where.not(id: tagged_post_ids).order(:id)

      assert_equal expected.to_a, relation.to_a
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
      assert_match(/DISTINCT/i, relation.to_sql)
    end

    test "includes with where preserves result count when eager loading changes" do
      author = authors(:david)
      plain = Post.where(author_id: author.id).order(:id)
      included = Post.includes(:author).where(author_id: author.id).order(:id)

      assert_equal plain.to_a, included.to_a
      assert_equal plain.count, included.count
      assert_no_queries { included.load.each(&:author) }
    end

    test "includes with references and order preserves joined table ordering" do
      author = authors(:david)
      relation = Post.includes(:author).references(:author).where("authors.id = ?", author.id).order("authors.name ASC", "posts.id ASC")

      assert_equal Post.where(author_id: author.id).order(:id).to_a, relation.to_a
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "preload with where and order keeps parent query separate from joins" do
      author = authors(:david)
      relation = Post.preload(:author).where(author_id: author.id).order(:id)

      assert_equal Post.where(author_id: author.id).order(:id).to_a, relation.to_a
      assert_no_match(/JOIN/i, relation.to_sql)
      assert_no_queries { relation.load.each(&:author) }
    end

    test "eager load with select and distinct handles joined row duplication and projection" do
      relation = Post.eager_load(:comments).select("posts.id").distinct.order("posts.id ASC")
      records = relation.to_a

      assert_equal Post.order(:id).ids, records.map(&:id)
      assert_raises(ActiveModel::MissingAttributeError) { records.first.title }
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
      assert_match(/DISTINCT/i, relation.to_sql)
    end

    test "joins includes and preload on the same association keep join and preload behavior isolated" do
      author = authors(:david)
      relation = Post.joins(:author).includes(:author).preload(:author).where("authors.id = ?", author.id).order(:id)

      assert_equal Post.where(author_id: author.id).order(:id).to_a, relation.to_a
      assert_match(/JOIN/i, relation.to_sql)
      assert_no_queries { relation.load.each(&:author) }
    end

    test "group having and count preserve grouped result and having predicate" do
      relation = Post.group(:author_id).having("COUNT(*) > 1")
      expected = Post.all.group_by(&:author_id).transform_values(&:size).select { |_author_id, count| count > 1 }

      assert_equal expected, relation.count
      assert_match(/GROUP BY/i, relation.to_sql)
      assert_match(/HAVING/i, relation.to_sql)
    end

    test "group select and order keep aggregate projection ordered" do
      relation = Post.select("author_id, COUNT(*) AS posts_count").group(:author_id).order("posts_count DESC", "author_id ASC")
      expected = Post.all.group_by(&:author_id).transform_values(&:size).sort_by { |author_id, count| [-count, author_id || 0] }

      assert_equal expected.map(&:first), relation.map(&:author_id)
      assert_equal expected.map(&:last), relation.map { |record| record.posts_count.to_i }
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "left outer joins group and having keep rows with missing associations" do
      relation = Post.left_outer_joins(:taggings).group("posts.id").having("COUNT(taggings.id) = 0").order("posts.id ASC")
      tagged_post_ids = Tagging.where(taggable_type: "Post").select(:taggable_id)
      expected = Post.where.not(id: tagged_post_ids).order(:id)

      assert_equal expected.to_a, relation.to_a
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
      assert_match(/HAVING/i, relation.to_sql)
    end

    test "distinct group and count keep SQL shape and grouped return values" do
      relation = Post.select(:author_id).distinct.group(:author_id)
      expected = Post.distinct.pluck(:author_id).index_with { 1 }

      assert_equal expected, relation.count
      assert_match(/DISTINCT/i, relation.to_sql)
      assert_match(/GROUP BY/i, relation.to_sql)
    end

    test "calculate with includes and references keeps aggregate result" do
      author = authors(:david)
      relation = Post.includes(:author).references(:author).where("authors.id = ?", author.id)

      assert_equal Post.where(author_id: author.id).count, relation.count
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
    end

    test "order reorder and reverse order replace and invert ordering" do
      source = Post.order(:title)
      source_sql = source.to_sql
      reordered = source.reorder(id: :asc)
      reversed = reordered.reverse_order

      assert_equal Post.order(id: :asc).ids, reordered.ids
      assert_equal Post.order(id: :desc).ids, reversed.ids
      assert_equal source_sql, source.to_sql
    end

    test "select reselect and unscope select restore projection" do
      source = Post.select(:id, :title).order(:id)
      reselected = source.reselect(:id)
      restored = reselected.unscope(:select)

      assert_raises(ActiveModel::MissingAttributeError) { reselected.first.title }
      assert_equal Post.order(:id).first.title, restored.first.title
      assert_match(/SELECT "posts"\.\*/i, restored.to_sql)
    end

    test "group regroup and unscope group replace and remove grouping" do
      source = Post.group(:author_id)
      regrouped = source.regroup(:type)
      ungrouped = regrouped.unscope(:group)

      assert_equal Post.group(:type).count, regrouped.count
      assert_equal Post.count, ungrouped.count
      assert_no_match(/GROUP BY/i, ungrouped.to_sql)
    end

    test "only and except restrict retained relation clauses" do
      source = Post.where(author_id: authors(:david).id).order(:id).limit(1)
      where_only = source.only(:where)
      without_where = source.except(:where)

      assert_equal Post.where(author_id: authors(:david).id).order(:id).ids, where_only.order(:id).ids
      assert_nil where_only.limit_value
      assert_equal Post.order(:id).limit(1).ids, without_where.ids
    end
  end
end
