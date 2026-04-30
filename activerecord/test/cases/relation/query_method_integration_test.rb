# frozen_string_literal: true

require "pp"
require "cases/helper"
require "models/author"
require "models/comment"
require "models/developer"
require "models/post"
require "models/tagging"

module ActiveRecord
  class QueryMethodIntegrationTest < ActiveRecord::TestCase
    fixtures :authors, :posts, :comments, :developers, :taggings

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

    test "default scope with unscope and merge does not revive removed predicates" do
      default_author = authors(:david)
      merged_author = authors(:mary)
      klass = relation_test_post_class do
        default_scope { where(author_id: default_author.id) }
      end

      relation = klass.unscope(:where).merge(klass.unscoped.where(author_id: merged_author.id)).order(:id)

      assert_equal Post.where(author_id: merged_author.id).order(:id).ids, relation.ids
      assert_no_match(/#{default_author.id}.*#{merged_author.id}/, relation.to_sql)
    end

    test "default scope where with where and rewhere keeps replacement boundary" do
      author = authors(:david)
      post = posts(:welcome)
      klass = relation_test_post_class do
        default_scope { where(author_id: author.id) }
      end

      relation = klass.where(title: "missing title").rewhere(title: post.title)

      assert_equal [post.id], relation.ids
      assert_equal [author.id], relation.pluck(:author_id).uniq
    end

    test "default scope order with order and reorder keeps explicit ordering precedence" do
      klass = relation_test_post_class do
        default_scope { order(title: :asc) }
      end
      source = klass.order(id: :desc)
      source_sql = source.to_sql
      reordered = source.reorder(id: :asc)

      assert_equal Post.order(id: :asc).ids, reordered.ids
      assert_match(/ORDER BY/i, source_sql)
      assert_equal source_sql, source.to_sql
    end

    test "default scope limit with limit and unscope limit handles overwrite and removal" do
      klass = relation_test_post_class do
        default_scope { limit(1) }
      end

      assert_equal 2, klass.limit(2).to_a.size
      assert_equal Post.count, klass.unscope(:limit).count
      assert_nil klass.unscope(:limit).limit_value
    end

    test "default scope select with select and reselect separates accumulated and replaced projections" do
      klass = relation_test_post_class do
        default_scope { select(:id) }
      end
      selected = klass.select(:title).order(:id)
      reselected = selected.reselect(:id)

      assert_equal Post.order(:id).first.title, selected.first.title
      assert_raises(ActiveModel::MissingAttributeError) { reselected.first.title }
      assert_match(/SELECT "posts"\."id"/i, reselected.to_sql)
    end

    test "default scope joins with left outer joins and where keeps join clauses distinct" do
      author = authors(:david)
      klass = relation_test_post_class do
        belongs_to :author, class_name: "Author", foreign_key: :author_id, inverse_of: false
        has_many :comments, class_name: "Comment", foreign_key: :post_id, inverse_of: false
        default_scope { joins(:author) }
      end
      relation = klass.left_outer_joins(:comments).where(authors: { id: author.id }).distinct.order(:id)

      assert_equal Post.where(author_id: author.id).order(:id).ids, relation.ids
      assert_match(/INNER JOIN/i, relation.to_sql)
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
    end

    test "default scope includes with references and order keeps eager loading join" do
      author = authors(:david)
      klass = relation_test_post_class do
        belongs_to :author, class_name: "Author", foreign_key: :author_id, inverse_of: false
        default_scope { includes(:author) }
      end
      relation = klass.references(:author).where("authors.id = ?", author.id).order("authors.name ASC", "posts.id ASC")

      assert_equal Post.where(author_id: author.id).order(:id).ids, relation.ids
      assert_match(/LEFT OUTER JOIN/i, relation.to_sql)
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "default scope with named scope and merge keeps composition order predicates" do
      author = authors(:david)
      post = posts(:welcome)
      klass = relation_test_post_class do
        default_scope { where(author_id: author.id) }
        scope :with_title, ->(title) { where(title: title) }
      end

      relation = klass.with_title(post.title).merge(klass.where(type: post.type))

      assert_equal [post.id], relation.ids
      assert_equal [author.id], relation.pluck(:author_id).uniq
    end

    test "default scope with association scope and merge keeps parent and association predicates" do
      author = authors(:david)
      post = posts(:welcome)
      klass = relation_test_post_class do
        belongs_to :author, -> { where(id: author.id) }, class_name: "Author", foreign_key: :author_id, inverse_of: false
        default_scope { where(type: "Post") }
      end

      relation = klass.joins(:author).merge(Author.where(name: author.name)).where(title: post.title)

      assert_equal [post.id], relation.ids
      assert_match(/JOIN/i, relation.to_sql)
      assert_match(/"posts"\."type" = 'Post'/, relation.to_sql)
    end

    test "default scope with unscoped block and nested relation reuse does not leak outside" do
      author = authors(:david)
      post = posts(:welcome)
      klass = relation_test_post_class do
        default_scope { where(author_id: author.id) }
      end
      scoped = klass.where(title: post.title)

      inside_count = klass.unscoped { klass.where(title: post.title).count }
      reused_ids = klass.unscoped { scoped.ids }

      assert_equal Post.where(title: post.title).count, inside_count
      assert_equal [post.id], reused_ids
      assert_equal Post.where(author_id: author.id).order(:id).ids, klass.order(:id).ids
    end

    test "default scope with none and or does not revive empty relation incorrectly" do
      author = authors(:david)
      post = posts(:welcome)
      klass = relation_test_post_class do
        default_scope { where(author_id: author.id) }
      end

      relation = klass.none.or(klass.where(id: post.id))

      assert_equal [post.id], relation.ids
      assert_empty klass.none.to_a
      assert_match(/"posts"\."author_id" = #{author.id}/, relation.to_sql)
    end

    test "default scope with readonly and update all keeps default mutation conditions" do
      author = authors(:david)
      klass = relation_test_post_class do
        default_scope { where(author_id: author.id).readonly }
      end
      body = "updated through default scoped update_all"

      assert_equal Post.where(author_id: author.id).count, klass.update_all(body: body)
      assert_equal [body], Post.where(author_id: author.id).distinct.pluck(:body)
      assert_empty Post.where.not(author_id: author.id).where(body: body)
    end

    test "default scope with strict loading and includes keeps association policy" do
      author = authors(:david)
      klass = relation_test_post_class do
        belongs_to :author, class_name: "Author", foreign_key: :author_id, inverse_of: false
        default_scope { strict_loading.includes(:author) }
      end
      records = klass.where(author_id: author.id).order(:id).to_a

      assert records.all?(&:strict_loading?)
      assert_no_queries { records.each(&:author) }
    end

    test "order limit and offset return deterministic paging results" do
      relation = Post.order(id: :asc).limit(3).offset(2)

      assert_equal Post.order(id: :asc).pluck(:id)[2, 3], relation.ids
      assert_equal 3, relation.limit_value
      assert_equal 2, relation.offset_value
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "limit reorder and first last keep finder order corrections bounded" do
      relation = Post.limit(2).reorder(id: :asc)

      assert_equal Post.order(id: :asc).limit(2).first, relation.first
      assert_equal Post.order(id: :asc).limit(2).last, relation.last
      assert_equal Post.order(id: :asc).limit(2).ids, relation.ids
    end

    test "in batches with where and order separates batch order from user order" do
      relation = Post.where.not(author_id: nil).order(title: :desc)
      batches = relation.in_batches(of: 3, error_on_ignore: false).map { |batch| batch.order(title: :desc).ids }

      assert_equal relation.pluck(:id).sort, batches.flatten.sort
      assert batches.all? { |ids| ids == Post.where(id: ids).order(title: :desc).ids }
    end

    test "find each with limit and offset handles ignored order warning and limit bound" do
      relation = Post.order(title: :desc).limit(4).offset(1)
      previous_logger = ActiveRecord::Base.logger
      ActiveRecord::Base.logger = ActiveSupport::Logger.new(nil)
      ids = nil

      assert_called(ActiveRecord::Base.logger, :warn) do
        ids = relation.find_each(batch_size: 2, error_on_ignore: false).map(&:id)
      end

      assert_equal 4, ids.size
      assert_not_equal relation.ids, ids
    ensure
      ActiveRecord::Base.logger = previous_logger
    end

    test "with from and joins keep CTE and from subquery aliases" do
      author = authors(:david)
      cte = Post.where(author_id: author.id)
      relation = Post.with(posts_by_author: cte)
        .from("posts_by_author AS posts")
        .joins(:author)
        .where("authors.id = ?", author.id)
        .order(:id)

      assert_equal Post.where(author_id: author.id).order(:id).ids, relation.ids
      assert_match(/WITH/i, relation.to_sql)
      assert_match(/posts_by_author AS posts/i, relation.to_sql)
      assert_match(/JOIN/i, relation.to_sql)
    end

    test "with recursive with where and order keeps recursive CTE and predicates" do
      relation = Post.with_recursive(post_ids: Post.where(id: posts(:welcome).id).select(:id))
        .joins("JOIN post_ids ON post_ids.id = posts.id")
        .where(author_id: authors(:david).id)
        .order(:id)

      assert_equal [posts(:welcome).id], relation.ids
      assert_match(/WITH RECURSIVE/i, relation.to_sql)
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "from select and where handle table alias and selected attributes" do
      relation = Post.from("posts AS aliased_posts")
        .select("aliased_posts.id, aliased_posts.title")
        .where("aliased_posts.author_id = ?", authors(:david).id)
        .order("aliased_posts.id ASC")
      record = relation.first

      assert_equal posts(:welcome).id, record.id
      assert_equal posts(:welcome).title, record.title
      assert_raises(ActiveModel::MissingAttributeError) { record.body }
      assert_match(/aliased_posts/, relation.to_sql)
    end

    test "lock joins and where keep lock intent after relation composition" do
      author = authors(:david)
      relation = Post.lock.joins(:author).where("authors.id = ?", author.id).order(:id)

      assert_equal Post.where(author_id: author.id).order(:id).ids, relation.ids
      assert relation.lock_value
      assert_match(/JOIN/i, relation.to_sql)
    end

    test "readonly strict loading and includes keep loading policy through associations" do
      author = authors(:david)
      records = Post.readonly.strict_loading.includes(:author).where(author_id: author.id).order(:id).to_a

      assert records.all?(&:readonly?)
      assert records.all?(&:strict_loading?)
      assert_no_queries { records.each(&:author) }
    end

    test "annotate optimizer hints and where keep SQL comments with predicates" do
      relation = Post.optimizer_hints("SeqScan(posts)").annotate("query method integration").where(author_id: authors(:david).id)

      assert_equal Post.where(author_id: authors(:david).id).order(:id).ids, relation.order(:id).ids
      assert_match(/SeqScan\(posts\)/, relation.to_sql)
      assert_match(/query method integration/, relation.to_sql)
      assert_match(/WHERE/i, relation.to_sql)
    end

    test "where update all limits mutation to scope and keeps relation reusable" do
      relation = Developer.where(name: "Jamis")
      relation_sql = relation.to_sql

      assert_equal Developer.where(name: "Jamis").count, relation.update_all(salary: 12345)
      assert_equal [12345], relation.distinct.pluck(:salary)
      assert_equal relation_sql, relation.to_sql
      assert_empty Developer.where.not(name: "Jamis").where(salary: 12345)
    end

    test "where delete all keeps join and default scope conditions" do
      author = authors(:david)
      klass = relation_test_post_class do
        belongs_to :author, class_name: "Author", foreign_key: :author_id, inverse_of: false
        default_scope { where(type: "Post") }
      end
      relation = klass.joins(:author).where("authors.id = ?", author.id).where(title: posts(:welcome).title)

      assert_equal 1, relation.delete_all
      assert_empty Post.where(id: posts(:welcome).id)
      assert Post.where(id: posts(:thinking).id).exists?
    end

    test "where touch all with order keeps scoped timestamp updates" do
      relation = Developer.where(name: "Jamis").order(:salary)
      before = Time.utc(2000, 1, 1)
      Developer.update_all(updated_at: before)

      assert_equal Developer.where(name: "Jamis").count, relation.touch_all(:updated_at)
      assert_operator Developer.where(name: "Jamis").minimum(:updated_at), :>, before
      assert_equal [before], Developer.where.not(name: "Jamis").distinct.pluck(:updated_at)
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "insert all returning keeps SQLite result shape independent of select" do
      rows = [
        { title: "bulk insert returning one", body: "body", type: "Post", author_id: authors(:david).id },
        { title: "bulk insert returning two", body: "body", type: "Post", author_id: authors(:david).id },
      ]

      result = Post.select(:id).insert_all(rows, returning: %w[id title])

      assert_equal %w[id title], result.columns
      assert_equal rows.map { |row| row[:title] }, result.rows.map(&:last)
    end

    test "upsert all with unique by handles conflict rows from scoped source data" do
      post = posts(:welcome)
      rows = Post.where(id: post.id).map do |record|
        { id: record.id, title: "upserted #{record.id}", body: record.body, type: record.type, author_id: record.author_id }
      end

      result = Post.upsert_all(rows, unique_by: :id, returning: %w[id title])

      assert_equal [[post.id, "upserted #{post.id}"]], result.rows
      assert_equal "upserted #{post.id}", Post.find(post.id).title
    end

    test "count by sql and async count by sql return integer counts from sanitized SQL" do
      sql = ["SELECT COUNT(*) FROM posts WHERE author_id = ?", authors(:david).id]
      expected = Post.where(author_id: authors(:david).id).count

      assert_equal expected, Post.count_by_sql(sql)
      assert_equal expected, Post.async_count_by_sql(sql).value
    end

    test "find by sql and async find by sql instantiate matching records with blocks" do
      sql = ["SELECT * FROM posts WHERE author_id = ? ORDER BY id ASC", authors(:david).id]
      sync_records = Post.find_by_sql(sql) { |record| record.readonly! }
      async_records = Post.async_find_by_sql(sql).value

      assert_equal Post.where(author_id: authors(:david).id).order(:id).ids, sync_records.map(&:id)
      assert sync_records.all?(&:readonly?)
      assert_equal sync_records.map(&:id), async_records.map(&:id)
    end

    test "relation equality compares relations arrays and association collections" do
      author = authors(:david)
      relation = Post.where(author_id: author.id).order(:id)
      same_relation = Post.where(author_id: author.id).order(:id)
      different_relation = Post.where(author_id: author.id).order(id: :desc)

      assert_equal relation, same_relation
      assert_not_equal relation, different_relation
      assert_equal relation, relation.to_a
      assert_equal author.posts.order(:id), relation
    end

    test "relation any and blank respect none loaded and block forms" do
      relation = Post.where(author_id: authors(:david).id)
      none = Post.none

      assert_predicate relation, :any?
      assert relation.any? { |post| post.author_id == authors(:david).id }
      assert_not_predicate none, :any?
      assert_not_predicate relation, :blank?
      assert_predicate none, :blank?
    end

    test "relation cache key version and key with version use timestamp column" do
      previous = Developer.collection_cache_versioning
      Developer.collection_cache_versioning = true
      relation = Developer.where(name: "Jamis").order(:id)
      relation.load
      cache_key = relation.cache_key(:updated_at)
      cache_version = relation.cache_version(:updated_at)

      assert_match(%r{developers/query-}, cache_key)
      assert_match(/\A\d+-\d{14}/, cache_version)
      assert_equal "#{cache_key}-#{cache_version}", relation.cache_key_with_version
    ensure
      Developer.collection_cache_versioning = previous
    end

    test "relation create and create bang apply scoped attributes and blocks" do
      author = authors(:david)
      relation = Post.where(author_id: author.id, type: "Post")
      created = relation.create(title: "relation create", body: "created body") { |post| post.tags_count = 2 }
      created_bang = relation.create!(title: "relation create bang", body: "created bang body")

      assert_predicate created, :persisted?
      assert_equal author.id, created.author_id
      assert_equal 2, created.tags_count
      assert_predicate created_bang, :persisted?
      assert_equal author.id, created_bang.author_id
    end

    test "relation create or find by variants return existing rows on unique conflict" do
      post = posts(:welcome)
      attributes = { id: post.id, title: post.title, body: post.body, type: post.type, author_id: post.author_id }

      assert_equal post.id, Post.create_or_find_by(attributes).id
      assert_equal post.id, Post.create_or_find_by!(attributes).id
      assert_equal 1, Post.where(id: post.id).count
    end

    test "relation delete and delete all remove scoped rows without instantiation" do
      first = Post.create!(title: "relation delete", body: "delete body", type: "Post", author_id: authors(:david).id)
      second = Post.create!(title: "relation delete all", body: "delete all body", type: "Post", author_id: authors(:david).id)
      relation = Post.where(author_id: authors(:david).id)

      assert_equal 1, relation.delete(first.id)
      assert_equal 1, relation.where(id: second.id).delete_all
      assert_empty Post.where(id: [first.id, second.id])
    end

    test "relation delete by removes rows matching additional conditions" do
      post = Post.create!(title: "relation delete by", body: "delete by body", type: "Post", author_id: authors(:david).id)
      relation = Post.where(author_id: authors(:david).id)

      assert_equal 1, relation.delete_by(title: post.title)
      assert_empty Post.where(id: post.id)
    end

    test "relation destroy and destroy all instantiate and remove scoped rows" do
      first = Post.create!(title: "relation destroy", body: "destroy body", type: "Post", author_id: authors(:david).id)
      second = Post.create!(title: "relation destroy all", body: "destroy all body", type: "Post", author_id: authors(:david).id)
      relation = Post.where(author_id: authors(:david).id)

      destroyed = relation.destroy(first.id)
      destroyed_all = relation.where(id: second.id).destroy_all

      assert_predicate destroyed, :destroyed?
      assert_equal [second.id], destroyed_all.map(&:id)
      assert destroyed_all.all?(&:destroyed?)
      assert_empty Post.where(id: [first.id, second.id])
    end

    test "relation destroy by returns destroyed records for matching conditions" do
      post = Post.create!(title: "relation destroy by", body: "destroy by body", type: "Post", author_id: authors(:david).id)
      relation = Post.where(author_id: authors(:david).id)

      destroyed = relation.destroy_by(title: post.title)

      assert_equal [post.id], destroyed.map(&:id)
      assert destroyed.all?(&:destroyed?)
      assert_empty Post.where(id: post.id)
    end

    test "relation eager loading detects includes that require joins" do
      preload_relation = Post.includes(:author).where(author_id: authors(:david).id)
      eager_relation = Post.includes(:author).references(:author).where("authors.id = ?", authors(:david).id)

      assert_not_predicate preload_relation, :eager_loading?
      assert_predicate eager_relation, :eager_loading?
      assert_match(/LEFT OUTER JOIN/i, eager_relation.to_sql)
    end

    test "relation empty respects none unloaded and loaded states" do
      existing = Post.where(author_id: authors(:david).id)
      missing = Post.where(id: -1)

      assert_not_predicate existing, :empty?
      assert_predicate missing, :empty?
      assert_predicate Post.none, :empty?
      assert_predicate missing.load, :empty?
    end

    test "relation encode with serializes loaded records as a sequence" do
      relation = Post.where(author_id: authors(:david).id).order(:id)
      coder = Class.new do
        attr_reader :tag, :records

        def represent_seq(tag, records)
          @tag = tag
          @records = records
        end
      end.new

      relation.encode_with(coder)

      assert_nil coder.tag
      assert_equal relation.to_a, coder.records
    end

    test "relation explain returns a proxy that explains executed SQL" do
      explanation = Post.where(author_id: authors(:david).id).order(:id).explain.inspect

      assert_match(/EXPLAIN/i, explanation)
      assert_match(/SELECT/i, explanation)
      assert_match(/posts/i, explanation)
    end

    test "relation find or create variants and initialize keep scoped defaults" do
      relation = Post.where(author_id: authors(:david).id, type: "Post")
      found = relation.find_or_create_by(title: posts(:welcome).title)
      created = relation.find_or_create_by!(title: "find or create bang") { |post| post.body = "bang body" }
      initialized = relation.find_or_initialize_by(title: "find or initialize") { |post| post.body = "init body" }

      assert_equal posts(:welcome).id, found.id
      assert_predicate created, :persisted?
      assert_equal authors(:david).id, created.author_id
      assert_not_predicate initialized, :persisted?
      assert_equal authors(:david).id, initialized.author_id
      assert_equal "init body", initialized.body
    end

    test "relation initialize and initialize copy set independent relation state" do
      relation = ActiveRecord::Relation.new(Post)
      source = Post.where(author_id: authors(:david).id)
      copied = source.dup
      narrowed = copied.where(title: posts(:welcome).title)

      assert_equal Post, relation.model
      assert_not_predicate relation, :loaded?
      assert_equal source.to_sql, copied.to_sql
      assert_not_equal source.to_sql, narrowed.to_sql
    end

    test "relation insert variants return SQLite result rows" do
      relation = Post.create_with(type: "Post", author_id: authors(:david).id, body: "bulk body")
      one = relation.insert({ title: "relation insert" }, returning: %w[id title])
      one_bang = relation.insert!({ title: "relation insert bang" }, returning: %w[id title])
      many = relation.insert_all([{ title: "relation insert all" }], returning: %w[id title])
      many_bang = relation.insert_all!([{ title: "relation insert all bang" }], returning: %w[id title])

      assert_equal ["relation insert"], one.rows.map(&:last)
      assert_equal ["relation insert bang"], one_bang.rows.map(&:last)
      assert_equal ["relation insert all"], many.rows.map(&:last)
      assert_equal ["relation insert all bang"], many_bang.rows.map(&:last)
      assert Post.where(title: ["relation insert", "relation insert bang", "relation insert all", "relation insert all bang"], author_id: authors(:david).id).exists?
    end

    test "relation inspect and pretty print summarize limited records" do
      relation = Post.where(author_id: authors(:david).id).order(:id).limit(1)
      inspected = relation.inspect
      output = +""
      pp = PP.new(output)

      relation.pretty_print(pp)
      pp.flush

      assert_match(/ActiveRecord::Relation/, inspected)
      assert_match(/Welcome to the weblog/, inspected)
      assert_match(/Welcome to the weblog/, output)
    end

    test "relation joined includes values reports overlapping joins and includes" do
      relation = Post.includes(:author, :comments).joins(:author)

      assert_equal [:author], relation.joined_includes_values
      assert_predicate relation, :eager_loading?
    end

    test "relation load load async scheduled reload and reset manage loaded state" do
      relation = Post.where(author_id: authors(:david).id).order(:id)

      assert_same relation, relation.load
      assert_predicate relation, :loaded?
      first_ids = relation.records.map(&:id)
      assert_same relation, relation.reset
      assert_not_predicate relation, :loaded?
      assert_not_predicate relation, :scheduled?
      assert_same relation, relation.load_async
      assert_predicate relation, :loaded?
      assert_not_predicate relation, :scheduled?
      assert_equal first_ids, relation.reload.records.map(&:id)
    end

    test "relation one many and none predicates handle none loaded and block forms" do
      one_relation = Post.where(id: posts(:welcome).id)
      many_relation = Post.where(author_id: authors(:david).id)
      none_relation = Post.none

      assert_predicate one_relation, :one?
      assert_not_predicate one_relation, :many?
      assert_predicate many_relation, :many?
      assert many_relation.one? { |post| post.id == posts(:welcome).id }
      assert_not_predicate none_relation, :one?
      assert_predicate none_relation, :none?
      assert many_relation.none? { |post| post.author_id == -1 }
    end

    test "relation new readonly and scope for create preserve scope defaults" do
      relation = Post.where(author_id: authors(:david).id, type: "Post").create_with(body: "scope body").readonly
      record = relation.new(title: "relation new")
      scope = relation.scope_for_create

      assert_not_predicate record, :persisted?
      assert_equal authors(:david).id, record.author_id
      assert_equal "scope body", record.body
      assert_predicate relation, :readonly?
      assert_equal({ "author_id" => authors(:david).id, "type" => "Post", "body" => "scope body" }, scope)
    end

    test "relation scoping size to ary and to sql keep scoped query behavior" do
      relation = Post.where(author_id: authors(:david).id).order(:id)

      scoped_ids = relation.scoping { Post.where(title: posts(:welcome).title).ids }
      array = relation.to_ary

      assert_equal [posts(:welcome).id], scoped_ids
      assert_equal Post.where(author_id: authors(:david).id).count, relation.size
      assert_equal relation.records, array
      assert_not_same relation.records, array
      assert_match(/WHERE/i, relation.to_sql)
      assert_match(/ORDER BY/i, relation.to_sql)
    end

    test "relation touch all update all and update counters mutate only scoped rows" do
      relation = Developer.where(name: "Jamis")
      baseline = Time.utc(2001, 1, 1)
      Developer.update_all(updated_at: baseline, salary: 100)

      assert_equal relation.count, relation.update_all(salary: 200)
      assert_equal [200], relation.distinct.pluck(:salary)
      assert_equal [100], Developer.where.not(name: "Jamis").distinct.pluck(:salary)

      assert_equal relation.count, relation.update_counters(salary: 5)
      assert_equal [205], relation.distinct.pluck(:salary)

      assert_equal relation.count, relation.touch_all(:updated_at)
      assert_operator relation.minimum(:updated_at), :>, baseline
      assert_equal [baseline], Developer.where.not(name: "Jamis").distinct.pluck(:updated_at)
    end

    test "relation upsert and upsert all use scoped defaults and returning shape" do
      relation = Post.create_with(type: "Post", author_id: authors(:david).id, body: "upsert body")
      one = relation.upsert({ id: posts(:welcome).id, title: "relation upsert" }, unique_by: :id, returning: %w[id title])
      many = relation.upsert_all([{ id: posts(:thinking).id, title: "relation upsert all" }], unique_by: :id, returning: %w[id title])

      assert_equal [[posts(:welcome).id, "relation upsert"]], one.rows
      assert_equal [[posts(:thinking).id, "relation upsert all"]], many.rows
      assert_equal "relation upsert", Post.find(posts(:welcome).id).title
      assert_equal "relation upsert all", Post.find(posts(:thinking).id).title
    end

    test "batches find each find in batches and in batches honor cursor bounds" do
      relation = Developer.where("id >= ?", developers(:dev_3).id)
      expected_ids = relation.order(:id).ids.first(5)

      each_ids = relation.find_each(start: expected_ids.first, finish: expected_ids.last, batch_size: 2).map(&:id)
      batch_ids = relation.find_in_batches(start: expected_ids.first, finish: expected_ids.last, batch_size: 2).map { |batch| batch.map(&:id) }
      relation_batches = relation.in_batches(of: 2, start: expected_ids.first, finish: expected_ids.last).map(&:ids)

      assert_equal expected_ids, each_ids
      assert_equal expected_ids, batch_ids.flatten
      assert_equal expected_ids, relation_batches.flatten
    end

    test "batch enumerator exposes batch size and yields records and relations" do
      enumerator = Developer.where("id <= ?", developers(:dev_5).id).in_batches(of: 2)

      assert_equal 2, enumerator.batch_size
      assert_equal Developer.where("id <= ?", developers(:dev_5).id).order(:id).ids, enumerator.each_record.map(&:id)
      assert enumerator.each.all? { |batch| batch.is_a?(ActiveRecord::Relation) }
    end

    test "batch enumerator update all touch all delete all and destroy all affect scoped rows" do
      Developer.update_all(salary: 100, updated_at: Time.utc(2001, 1, 1))
      update_scope = Developer.where(id: [developers(:dev_3).id, developers(:dev_4).id]).in_batches(of: 1)

      assert_equal 2, update_scope.update_all(salary: 321)
      assert_equal [321], Developer.where(id: [developers(:dev_3).id, developers(:dev_4).id]).distinct.pluck(:salary)
      assert_equal 2, update_scope.touch_all(:updated_at)
      assert_operator Developer.where(id: developers(:dev_3).id).pick(:updated_at), :>, Time.utc(2001, 1, 1)

      deletable = Post.where(id: [
        Post.create!(title: "batch delete one", body: "body", type: "Post", author_id: authors(:david).id).id,
        Post.create!(title: "batch delete two", body: "body", type: "Post", author_id: authors(:david).id).id,
      ])
      destroyable = Post.where(id: [
        Post.create!(title: "batch destroy one", body: "body", type: "Post", author_id: authors(:david).id).id,
        Post.create!(title: "batch destroy two", body: "body", type: "Post", author_id: authors(:david).id).id,
      ])

      assert_equal 2, deletable.in_batches(of: 1).delete_all
      assert_empty deletable
      assert_equal 2, destroyable.in_batches(of: 1).destroy_all
      assert_empty destroyable
    end

    test "calculations async aggregate methods match synchronous results" do
      relation = Developer.where("salary > ?", 0)

      assert_equal relation.average(:salary), relation.async_average(:salary).value
      assert_equal relation.count, relation.async_count.value
      assert_equal relation.maximum(:salary), relation.async_maximum(:salary).value
      assert_equal relation.minimum(:salary), relation.async_minimum(:salary).value
      assert_equal relation.sum(:salary), relation.async_sum(:salary).value
    end

    test "calculations async ids pick and pluck match synchronous projections" do
      relation = Post.where(author_id: authors(:david).id).order(:id)

      assert_equal relation.ids, relation.async_ids.value
      assert_equal relation.pick(:title), relation.async_pick(:title).value
      assert_equal relation.pluck(:id, :title), relation.async_pluck(:id, :title).value
    end

    test "calculations synchronous methods keep grouped and scalar result shapes" do
      relation = Developer.where("salary > ?", 0)
      grouped = relation.group(:name)

      assert_equal relation.count(:all), relation.calculate(:count, :all)
      assert_equal relation.average(:salary), relation.calculate(:average, :salary)
      assert_equal relation.maximum(:salary), relation.calculate(:maximum, :salary)
      assert_equal relation.minimum(:salary), relation.calculate(:minimum, :salary)
      assert_equal relation.sum(:salary), relation.calculate(:sum, :salary)
      assert_equal grouped.count, grouped.calculate(:count, :all)
      assert_equal relation.order(:id).ids, relation.order(:id).ids
    end

    test "relation delegation exposes model and records public contracts" do
      relation = Post.where(author_id: authors(:david).id).order(:id)

      assert_includes ActiveRecord::Delegation.delegated_classes, ActiveRecord::Relation
      assert_kind_of Set, ActiveRecord::Delegation.uncacheable_methods
      assert_equal Post.table_name, relation.table_name
      assert_equal Post.name, relation.name
      assert_equal relation.records.length, relation.length
      assert_equal relation.records.first, relation[0]
      assert_equal relation.records.map(&:id), relation.each.map(&:id)
      assert_equal relation.records + [posts(:authorless)], relation + [posts(:authorless)]
    end

    test "finder methods locate records by id conditions and ordinal positions" do
      ordered = Post.order(:id)

      assert_predicate ordered, :exists?
      assert ordered.exists?(posts(:welcome).id)
      assert_equal posts(:welcome), ordered.find(posts(:welcome).id)
      assert_equal posts(:welcome), ordered.find_by(title: posts(:welcome).title)
      assert_equal posts(:welcome), ordered.find_by!(title: posts(:welcome).title)
      assert_equal ordered.limit(1).where(id: posts(:welcome).id).sole, ordered.find_sole_by(id: posts(:welcome).id)
      assert_equal ordered.offset(3).first, ordered.fourth
      assert_equal ordered.offset(4).first, ordered.fifth
      assert_nil ordered.forty_two
      assert_equal ordered.first, ordered.first
      assert_equal ordered.last, ordered.last
    end

    test "finder bang ordinal methods raise when position is missing" do
      empty = Post.where(id: -1)

      assert_raises(ActiveRecord::RecordNotFound) { empty.first! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.fourth! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.fifth! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.forty_two! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.find_by!(title: "missing") }
    end

    test "finder include checks loaded records and unloaded relation membership" do
      relation = Post.where(author_id: authors(:david).id).order(:id)
      post = posts(:welcome)

      assert_includes relation, post
      assert_not_includes relation, posts(:authorless)
      relation.load
      assert_includes relation, post
    end

    test "finder remaining ordinal methods return expected ordered records" do
      ordered = Post.order(:id)

      records = ordered.to_a

      assert_equal records[1], ordered.second
      assert_equal records[2], ordered.third
      assert_equal records[-2], ordered.second_to_last
      assert_equal records[-3], ordered.third_to_last
      assert_equal records.last, ordered.last!
      assert_equal records.first, ordered.take
    end

    test "finder remaining bang ordinal methods raise when missing" do
      empty = Post.where(id: -1)

      assert_raises(ActiveRecord::RecordNotFound) { empty.second! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.third! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.second_to_last! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.third_to_last! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.last! }
      assert_raises(ActiveRecord::RecordNotFound) { empty.take! }
    end

    test "finder sole returns exactly one record and raises for none or many" do
      sole_relation = Post.where(id: posts(:welcome).id)
      empty_relation = Post.where(id: -1)
      many_relation = Post.where(author_id: authors(:david).id)

      assert_equal posts(:welcome), sole_relation.sole
      assert_raises(ActiveRecord::RecordNotFound) { empty_relation.sole }
      assert_raises(ActiveRecord::SoleRecordExceeded) { many_relation.sole }
    end

    test "relation from clause public contract keeps value name equality and emptiness" do
      empty = ActiveRecord::Relation::FromClause.empty
      clause = ActiveRecord::Relation::FromClause.new("posts AS aliased_posts", "aliased_posts")
      same = ActiveRecord::Relation::FromClause.new("posts AS aliased_posts", "aliased_posts")
      different = ActiveRecord::Relation::FromClause.new("posts", nil)

      assert_predicate empty, :empty?
      assert_not_predicate clause, :empty?
      assert_equal clause, same
      assert_not_equal clause, different
      assert_same clause, clause.merge(different)
      assert_equal "aliased_posts", clause.name
      assert_equal "posts AS aliased_posts", clause.value
    end

    test "relation merger public contract combines hash and relation values" do
      base = Post.where(author_id: authors(:david).id)
      merged_hash = base.merge(order: [:id], limit: 2, create_with: { body: "merged body" })
      merged_relation = base.merge(Post.where(title: posts(:welcome).title).reorder(id: :desc).includes(:author))

      assert_equal Post.where(author_id: authors(:david).id).order(:id).limit(2).ids, merged_hash.ids
      assert_equal "merged body", merged_hash.scope_for_create["body"]
      assert_equal [posts(:welcome).id], merged_relation.ids
      assert_equal [:author], merged_relation.includes_values
      assert_match(/ORDER BY "posts"\."id" DESC/i, merged_relation.to_sql)
    end

    test "predicate builder handles arrays ranges relations associations and polymorphic values" do
      author = authors(:david)
      post = posts(:welcome)
      relation = Post.where(id: [post.id, nil, (posts(:thinking).id..posts(:thinking).id)]).order(:id)
      subquery = Post.where(id: Post.where(author_id: author.id))
      association = Post.where(author: author)
      polymorphic = Tagging.where(taggable: [post, posts(:thinking), nil]).order(:id)

      assert_equal [post.id, posts(:thinking).id], relation.ids
      assert_equal Post.where(author_id: author.id).order(:id).ids, subquery.order(:id).ids
      assert_equal Post.where(author_id: author.id).order(:id).ids, association.order(:id).ids
      assert_equal Tagging.where(taggable_type: "Post", taggable_id: [post.id, posts(:thinking).id]).or(Tagging.where(taggable_id: nil)).order(:id).ids, polymorphic.ids
    end

    test "query attribute compares database values and detects nil infinite and unboundable values" do
      integer_type = Post.type_for_attribute("id")
      attr = ActiveRecord::Relation::QueryAttribute.new("id", "1", integer_type)
      same = ActiveRecord::Relation::QueryAttribute.new("id", "1", integer_type)
      nil_attr = ActiveRecord::Relation::QueryAttribute.new("id", nil, integer_type)
      infinite_attr = ActiveRecord::Relation::QueryAttribute.new("id", Float::INFINITY, integer_type)

      assert_equal 1, attr.value_for_database
      assert_equal attr, same
      assert_equal attr.hash, same.hash
      assert_predicate nil_attr, :nil?
      assert_predicate infinite_attr, :infinite?
      assert_nil attr.unboundable?
      assert_equal 2, attr.with_cast_value(2).value_for_database
    end

    private
      def relation_test_post_class(&block)
        klass = Class.new(ActiveRecord::Base)
        self.class.const_set("RelationTestPost#{object_id.abs}", klass)
        klass.class_eval do
          self.table_name = "posts"
          self.inheritance_column = :_type_disabled
          class_eval(&block)
        end
        klass
      end
  end
end
