# frozen_string_literal: true

require "pp"
require "cases/helper"
require "models/computer"
require "models/developer"
require "models/project"
require "models/company"
require "models/categorization"
require "models/category"
require "models/post"
require "models/author"
require "models/book"
require "models/comment"
require "models/tag"
require "models/tagging"
require "models/person"
require "models/reader"
require "models/ship_part"
require "models/ship"
require "models/liquid"
require "models/molecule"
require "models/electron"
require "models/human"
require "models/interest"
require "models/pirate"
require "models/parrot"
require "models/bird"
require "models/treasure"
require "models/price_estimate"
require "models/invoice"
require "models/discount"
require "models/line_item"
require "models/shipping_line"
require "models/essay"
require "models/member"
require "models/membership"
require "models/sharded"
require "models/cpk"
require "models/member_detail"
require "models/organization"
require "models/dog"
require "models/other_dog"


class AssociationsTest < ActiveRecord::TestCase
  def test_associations_eager_load
    assert_nothing_raised do
      ActiveRecord::Associations.eager_load!
    end
  end

  def test_dup_clears_association_cache
    post = posts(:welcome)
    post.association(:comments)

    assert post.association_cached?(:comments)
    assert_not post.dup.association_cached?(:comments)
  end

  def test_alias_tracker_merges_supplied_alias_counts_with_join_counts
    aliases = Hash.new { 2 }
    joins = [Arel::Nodes::StringJoin.new('JOIN comments ON comments.post_id = posts.id')]

    tracker = ActiveRecord::Associations::AliasTracker.create(ActiveRecord::Base.connection_pool, "posts", joins, aliases)

    assert_equal 3, tracker.aliases["comments"]
    assert_equal 2, tracker.aliases["tags"]
  end

  def test_alias_tracker_rejects_non_arel_join_nodes
    error = assert_raises(ArgumentError) do
      ActiveRecord::Associations::AliasTracker.initial_count_for(ActiveRecord::Base.lease_connection, "posts", [Object.new])
    end

    assert_equal "joins list should be initialized by list of Arel::Nodes::Join", error.message
  end

  def test_association_target_resolves_promise
    association = posts(:welcome).association(:comments)
    association.instance_variable_set(:@target, ActiveRecord::Promise::Complete.new(:resolved_target))

    assert_equal :resolved_target, association.target
    assert_equal :resolved_target, association.instance_variable_get(:@target)
  end

  def test_association_load_target_resets_when_record_not_found
    association = posts(:welcome).association(:comments)
    association.singleton_class.define_method(:find_target?) { true }
    association.singleton_class.define_method(:find_target) { |async: false| raise ActiveRecord::RecordNotFound }

    assert_nil ActiveRecord::Associations::Association.instance_method(:load_target).bind_call(association)
    assert_not association.loaded?
  end

  def test_association_async_load_target_uses_async_skip_statement_cache_path
    association = authors(:david).association(:posts_sorted_by_id)

    assert_nil association.async_load_target
    assert_predicate association, :loaded?
    assert_kind_of Array, association.target
  end

  def test_association_async_load_target_noops_when_already_loaded
    association = posts(:welcome).association(:comments)
    association.target = []

    assert_nil association.async_load_target
    assert_predicate association, :loaded?
    assert_equal [], association.target
  end

  def test_association_scope_uses_disable_joins_scope_when_configured
    association = authors(:david).association(:no_joins_comments)

    assert association.disable_joins
    assert_not_nil association.send(:association_scope)
  end

  def test_singular_association_find_target_uses_first_when_disable_joins_is_configured
    association = ActiveRecord::Associations::SingularAssociation.allocate
    scope = Struct.new(:first).new(:first_record)
    association.define_singleton_method(:disable_joins) { true }
    association.define_singleton_method(:scope) { scope }

    assert_equal :first_record, ActiveRecord::Associations::SingularAssociation.instance_method(:find_target).bind_call(association)
  end

  def test_singular_association_find_target_uses_async_first_when_disable_joins_is_configured
    association = ActiveRecord::Associations::SingularAssociation.allocate
    promise = Struct.new(:record) do
      def then
        yield [record]
      end
    end.new(:async_record)
    scope = Struct.new(:promise) do
      def load_async
        promise
      end
    end.new(promise)
    association.define_singleton_method(:disable_joins) { true }
    association.define_singleton_method(:scope) { scope }

    assert_equal :async_record, ActiveRecord::Associations::SingularAssociation.instance_method(:find_target).bind_call(association, async: true)
  end

  def test_singular_association_writer_requires_subclass_replace_implementation
    association = ActiveRecord::Associations::SingularAssociation.allocate

    error = assert_raises(NotImplementedError) do
      association.writer(Object.new)
    end

    assert_equal "Subclasses must implement a replace(record) method", error.message
  end

  def test_through_association_ensure_mutable_raises_for_has_one_non_belongs_to_source
    association = ActiveRecord::Associations::HasOneThroughAssociation.allocate
    source_reflection = through_source_reflection(belongs_to: false, macro: :has_one)
    reflection = through_reflection(has_one: true)
    association.define_singleton_method(:owner) { Object.new }
    association.define_singleton_method(:source_reflection) { source_reflection }
    association.define_singleton_method(:reflection) { reflection }

    assert_raises(ActiveRecord::HasOneThroughCantAssociateThroughHasOneOrManyReflection) do
      association.__send__(:ensure_mutable)
    end
  end

  def test_through_association_ensure_not_nested_raises_for_has_one_and_has_many
    has_one = ActiveRecord::Associations::HasOneThroughAssociation.allocate
    has_one_reflection = through_reflection(has_one: true, nested: true)
    has_one.define_singleton_method(:owner) { Object.new }
    has_one.define_singleton_method(:reflection) { has_one_reflection }

    assert_raises(ActiveRecord::HasOneThroughNestedAssociationsAreReadonly) do
      has_one.__send__(:ensure_not_nested)
    end

    has_many = ActiveRecord::Associations::HasManyThroughAssociation.allocate
    has_many_reflection = through_reflection(has_one: false, nested: true)
    has_many.define_singleton_method(:owner) { Object.new }
    has_many.define_singleton_method(:reflection) { has_many_reflection }

    assert_raises(ActiveRecord::HasManyThroughNestedAssociationsAreReadonly) do
      has_many.__send__(:ensure_not_nested)
    end
  end

  def test_through_association_build_record_without_inverse_skips_foreign_key_assignment
    association = ActiveRecord::Associations::HasManyThroughAssociation.allocate
    association.define_singleton_method(:source_reflection) do
      Struct.new(:collection?, :inverse_of).new(true, nil)
    end
    association.define_singleton_method(:through_association) do
      Struct.new(:target).new([])
    end

    assert_raises(NoMethodError) do
      association.__send__(:build_record, {})
    end
  end

  def test_through_association_build_record_with_collection_through_target_skips_inverse_assignment
    association = ActiveRecord::Associations::HasManyThroughAssociation.allocate
    inverse = Struct.new(:foreign_key).new(:post_id)
    association.define_singleton_method(:source_reflection) do
      Struct.new(:collection?, :inverse_of).new(true, inverse)
    end
    association.define_singleton_method(:through_association) do
      Struct.new(:target).new([Struct.new(:id).new(1)])
    end

    assert_raises(NoMethodError) do
      association.__send__(:build_record, {})
    end
  end

  def test_through_association_build_record_without_through_target_skips_inverse_assignment
    association = through_association_build_record_stub
    inverse = Struct.new(:foreign_key).new(:post_id)
    association.define_singleton_method(:source_reflection) do
      Struct.new(:collection?, :inverse_of).new(true, inverse)
    end
    association.define_singleton_method(:through_association) do
      Struct.new(:target).new(nil)
    end

    assert_equal({}, association.__send__(:build_record, {}))
  end

  def through_source_reflection(belongs_to:, macro: :has_many)
    Struct.new(:belongs_to?, :class_name, :macro).new(belongs_to, "JoinModel", macro)
  end

  def through_reflection(has_one:, nested: false)
    Struct.new(:name, :has_one?, :nested?, :source_reflection, :through_reflection).new(
      :through_records,
      has_one,
      nested,
      through_source_reflection(belongs_to: false),
      Struct.new(:class_name).new("ThroughModel")
    )
  end

  def through_association_build_record_stub
    base = Class.new do
      def build_record(attributes)
        attributes
      end
    end

    Class.new(base) do
      include ActiveRecord::Associations::ThroughAssociation
    end.new
  end

  def test_association_scope_is_nil_without_target_class
    association = posts(:welcome).association(:comments)
    association.singleton_class.define_method(:klass) { nil }

    assert_nil association.send(:association_scope)
  end

  def test_association_scope_merges_global_current_scope
    association = posts(:welcome).association(:comments)

    Comment.where(author_id: 1).scoping(all_queries: true) do
      assert_match(/author_id/, association.scope.to_sql)
    end
  end

  def test_association_default_foreign_key_present_is_false
    association = posts(:welcome).association(:comments)

    assert_not ActiveRecord::Associations::Association.instance_method(:foreign_key_present?).bind_call(association)
  end

  def test_foreign_association_detects_owner_foreign_key_presence_from_primary_key
    association = foreign_association_stub(
      reflection: foreign_association_reflection(klass_primary_key: "id", active_record_primary_key: "author_id"),
      owner: foreign_association_owner("author_id" => 1)
    )

    assert_predicate association, :foreign_key_present?

    association = foreign_association_stub(
      reflection: foreign_association_reflection(klass_primary_key: "id", active_record_primary_key: "author_id"),
      owner: foreign_association_owner("author_id" => nil)
    )

    assert_not_predicate association, :foreign_key_present?
  end

  def test_foreign_association_foreign_key_presence_is_false_without_primary_key
    association = foreign_association_stub(
      reflection: foreign_association_reflection(klass_primary_key: nil, active_record_primary_key: "author_id"),
      owner: foreign_association_owner("author_id" => 1)
    )

    assert_not_predicate association, :foreign_key_present?
  end

  def test_foreign_association_nullified_owner_attributes_include_foreign_keys_and_type
    association = foreign_association_stub(
      reflection: foreign_association_reflection(foreign_key: ["author_id", "tenant_id"], type: "author_type")
    )

    assert_equal({ "author_id" => nil, "tenant_id" => nil, "author_type" => nil }, association.nullified_owner_attributes)
  end

  def test_foreign_association_nullified_owner_attributes_omit_blank_type
    association = foreign_association_stub(
      reflection: foreign_association_reflection(foreign_key: "author_id", type: nil)
    )

    assert_equal({ "author_id" => nil }, association.nullified_owner_attributes)
  end

  def test_foreign_association_sets_owner_attributes_from_join_keys_and_polymorphic_type
    association = foreign_association_stub(
      reflection: foreign_association_reflection(
        join_primary_key: ["author_id", "tenant_id"],
        join_foreign_key: ["id", "tenant_id"],
        type: "author_type"
      ),
      owner: foreign_association_owner("id" => 7, "tenant_id" => 42)
    )
    record = foreign_association_record

    association.__send__(:set_owner_attributes, record)

    assert_equal({ "author_id" => 7, "tenant_id" => 42, "author_type" => "AssociationsTest::ForeignAssociationOwner" }, record.written_attributes)
  end

  def test_foreign_association_sets_owner_attributes_without_polymorphic_type
    association = foreign_association_stub(
      reflection: foreign_association_reflection(join_primary_key: "author_id", join_foreign_key: "id", type: nil),
      owner: foreign_association_owner("id" => 7)
    )
    record = foreign_association_record

    association.__send__(:set_owner_attributes, record)

    assert_equal({ "author_id" => 7 }, record.written_attributes)
  end

  def test_foreign_association_does_not_set_owner_attributes_for_through_association
    association = foreign_association_stub(
      reflection: foreign_association_reflection(join_primary_key: "author_id", join_foreign_key: "id"),
      owner: foreign_association_owner("id" => 7),
      options: { through: :authorships }
    )
    record = foreign_association_record

    association.__send__(:set_owner_attributes, record)

    assert_empty record.written_attributes
  end

  ForeignAssociationReflection = Struct.new(
    :klass, :active_record_primary_key, :foreign_key, :type, :join_primary_key, :join_foreign_key,
    keyword_init: true
  )

  ForeignAssociationKlass = Struct.new(:primary_key, keyword_init: true)

  ForeignAssociationOwner = Struct.new(:attributes, keyword_init: true) do
    def attribute_present?(name)
      attributes[name].present?
    end

    def _read_attribute(name)
      attributes[name]
    end

    def self.polymorphic_name
      name
    end
  end

  ForeignAssociationRecord = Struct.new(:written_attributes, keyword_init: true) do
    def _write_attribute(name, value)
      written_attributes[name] = value
    end
  end

  def foreign_association_stub(reflection:, owner: foreign_association_owner, options: {})
    Class.new do
      include ActiveRecord::Associations::ForeignAssociation

      attr_reader :reflection, :owner, :options

      def initialize(reflection, owner, options)
        @reflection = reflection
        @owner = owner
        @options = options
      end
    end.new(reflection, owner, options)
  end

  def foreign_association_reflection(
    klass_primary_key: "id",
    active_record_primary_key: "author_id",
    foreign_key: "author_id",
    type: nil,
    join_primary_key: "author_id",
    join_foreign_key: "id"
  )
    ForeignAssociationReflection.new(
      klass: ForeignAssociationKlass.new(primary_key: klass_primary_key),
      active_record_primary_key: active_record_primary_key,
      foreign_key: foreign_key,
      type: type,
      join_primary_key: join_primary_key,
      join_foreign_key: join_foreign_key
    )
  end

  def foreign_association_owner(attributes = {})
    ForeignAssociationOwner.new(attributes: attributes)
  end

  def foreign_association_record
    ForeignAssociationRecord.new(written_attributes: {})
  end

  def test_association_type_mismatch_raises_for_wrong_record_class
    association = posts(:welcome).association(:comments)

    error = assert_raises(ActiveRecord::AssociationTypeMismatch) do
      association.send(:raise_on_type_mismatch!, authors(:david))
    end

    assert_match(/Comment\(#\d+\) expected/, error.message)
    assert_match(/Author\(#\d+\)/, error.message)
  end

  def test_association_type_mismatch_accepts_record_matching_fresh_class_name
    association = posts(:welcome).association(:comments)
    original_reflection = association.reflection
    stale_class = Class.new
    fake_reflection = Struct.new(:klass, :class_name).new(stale_class, "Author")
    association.instance_variable_set(:@reflection, fake_reflection)

    assert_nothing_raised do
      association.send(:raise_on_type_mismatch!, authors(:david))
    end
  ensure
    association.instance_variable_set(:@reflection, original_reflection) if association && original_reflection
  end

  def test_association_enqueue_destroy_association_skips_without_job_class
    post = posts(:welcome)
    association = post.association(:comments)
    old_job = Post._destroy_association_async_job
    Post._destroy_association_async_job = nil

    assert_nil association.send(:enqueue_destroy_association, owner_model_name: "Post")
  ensure
    Post._destroy_association_async_job = old_job
  end

  def test_association_enqueue_destroy_association_records_job_after_commit
    post = posts(:welcome)
    association = post.association(:comments)
    job_class = Class.new
    old_job = Post._destroy_association_async_job
    Post._destroy_association_async_job = job_class
    post.define_singleton_method(:_after_commit_jobs) { @_after_commit_jobs ||= [] }

    association.send(:enqueue_destroy_association, owner_model_name: "Post")

    assert_equal [[job_class, { owner_model_name: "Post" }]], post._after_commit_jobs
  ensure
    Post._destroy_association_async_job = old_job
  end
  fixtures :accounts, :companies, :developers, :projects, :developers_projects,
           :computers, :people, :readers, :authors, :author_addresses, :author_favorites,
           :comments, :posts, :sharded_blogs, :sharded_blog_posts, :sharded_comments, :sharded_tags, :sharded_blog_posts_tags,
           :cpk_orders, :cpk_books, :cpk_reviews

  def test_eager_loading_should_not_change_count_of_children
    liquid = Liquid.create(name: "salty")
    molecule = liquid.molecules.create(name: "molecule_1")
    molecule.electrons.create(name: "electron_1")
    molecule.electrons.create(name: "electron_2")

    liquids = Liquid.includes(molecules: :electrons).references(:molecules).where("molecules.id is not null")
    assert_equal 1, liquids[0].molecules.length
  end

  def test_allocated_record_can_see_assocations
    assert_not_nil Ship.allocate.association(:parts)
  end

  def test_subselect
    author = authors :david
    favs = author.author_favorites
    fav2 = author.author_favorites.where(author: Author.where(id: author.id)).to_a
    assert_equal favs, fav2
  end

  def test_loading_the_association_target_should_keep_child_records_marked_for_destruction
    ship = Ship.create!(name: "The good ship Dollypop")
    part = ship.parts.create!(name: "Mast")
    part.mark_for_destruction
    assert_predicate ship.parts[0], :marked_for_destruction?
  end

  def test_loading_the_association_target_should_load_most_recent_attributes_for_child_records_marked_for_destruction
    ship = Ship.create!(name: "The good ship Dollypop")
    part = ship.parts.create!(name: "Mast")
    part.mark_for_destruction
    ShipPart.find(part.id).update_columns(name: "Deck")
    assert_equal "Deck", ship.parts[0].name
  end

  def test_loading_cpk_association_when_persisted_and_in_memory_differ
    order = Cpk::Order.create!(id: [1, 2], status: "paid")
    book = order.books.create!(id: [3, 4], title: "Book")

    Cpk::Book.find(book.id).update_columns(title: "A different title")
    order.books.load

    assert_equal [3, 4], book.id
  end

  def test_include_with_order_works
    assert_nothing_raised { Account.all.merge!(order: "id", includes: :firm).first }
    assert_nothing_raised { Account.all.merge!(order: :id, includes: :firm).first }
  end

  def test_bad_collection_keys
    assert_raise(ArgumentError, "ActiveRecord should have barked on bad collection keys") do
      Class.new(ActiveRecord::Base).has_many(:wheels, name: "wheels")
    end
  end

  def test_should_construct_new_finder_sql_after_create
    person = Person.new first_name: "clark"
    assert_equal [], person.readers.to_a
    person.save!
    reader = Reader.create! person: person, post: Post.new(title: "foo", body: "bar")
    assert person.readers.find(reader.id)
  end

  def test_force_reload
    firm = Firm.new("name" => "A New Firm, Inc")
    firm.save
    firm.clients.each { } # forcing to load all clients
    assert_predicate firm.clients, :empty?, "New firm shouldn't have client objects"
    assert_equal 0, firm.clients.size, "New firm should have 0 clients"

    client = Client.new("name" => "TheClient.com", "firm_id" => firm.id)
    client.save

    assert_predicate firm.clients, :empty?, "New firm should have cached no client objects"
    assert_equal 0, firm.clients.size, "New firm should have cached 0 clients count"

    firm.clients.reload

    assert_not firm.clients.empty?, "New firm should have reloaded client objects"
    assert_equal 1, firm.clients.size, "New firm should have reloaded clients count"
  end

  def test_using_limitable_reflections_helper
    using_limitable_reflections = lambda { |reflections| Tagging.all.send :using_limitable_reflections?, reflections }
    belongs_to_reflections = [Tagging.reflect_on_association(:tag), Tagging.reflect_on_association(:super_tag)]
    has_many_reflections = [Tag.reflect_on_association(:taggings), Developer.reflect_on_association(:projects)]
    mixed_reflections = (belongs_to_reflections + has_many_reflections).uniq
    assert using_limitable_reflections.call(belongs_to_reflections), "Belong to associations are limitable"
    assert_not using_limitable_reflections.call(has_many_reflections), "All has many style associations are not limitable"
    assert_not using_limitable_reflections.call(mixed_reflections), "No collection associations (has many style) should pass"
  end

  def test_association_with_references
    firm = companies(:first_firm)
    assert_equal [:foo], firm.association_with_references.references_values
  end

  def test_belongs_to_a_model_with_composite_foreign_key_finds_associated_record
    comment = sharded_comments(:great_comment_blog_post_one)
    blog_post = sharded_blog_posts(:great_post_blog_one)

    assert_equal(blog_post, comment.blog_post)
  end

  def test_belongs_to_a_model_with_composite_primary_key_sets_inverse_of
    order = cpk_orders(:cpk_groceries_order_1)
    store_id, _order_id = order.id
    book = order.books.create!(id: [store_id, 4], title: "Book")

    assert_same book.order, book.order.books.first.order
  end

  def test_belongs_to_a_model_with_composite_association_primary_key_sets_inverse_of
    cpk_order = cpk_orders(:cpk_groceries_order_1)
    store_id, order_id = cpk_order.id
    order = Cpk::NonCpkOrder.find(order_id)
    book = order.books_with_composite_primary_key.create!(id: [store_id, 4], title: "Book")
    book = Cpk::BookWithNonCpkOrder.find(book.id)
    associated_order = book.non_cpk_order
    associated_book = associated_order.books_with_composite_primary_key.to_a.find { |record| record.id == book.id }

    assert_same associated_order, associated_book.non_cpk_order
  end

  def test_belongs_to_a_cpk_model_by_id_attribute
    order = cpk_orders(:cpk_groceries_order_1)
    _order_shop_id, order_id = order.id
    agreement = Cpk::OrderAgreement.create(order_id: order_id, signature: "signed")

    assert_equal(order, agreement.order)
  end

  def test_belongs_to_a_model_with_composite_primary_key_uses_composite_pk_in_sql
    comment = sharded_comments(:great_comment_blog_post_one)

    sql = capture_sql do
      comment.blog_post
    end.first

    assert_match(/#{Regexp.escape(quote_table_name("sharded_blog_posts.blog_id"))} =/, sql)
    assert_match(/#{Regexp.escape(quote_table_name("sharded_blog_posts.id"))} =/, sql)
  end

  def test_querying_by_whole_associated_records_using_query_constraints
    comments = [sharded_comments(:great_comment_blog_post_one), sharded_comments(:great_comment_blog_post_two)]

    blog_posts = Sharded::BlogPost.where(comments: comments).to_a

    expected_posts = [sharded_blog_posts(:great_post_blog_one), sharded_blog_posts(:great_post_blog_two)]
    assert_equal(expected_posts.map(&:id).sort, blog_posts.map(&:id).sort)
  end

  def test_querying_by_single_associated_record_works_using_query_constraints
    comments = [sharded_comments(:great_comment_blog_post_one), sharded_comments(:great_comment_blog_post_two)]

    blog_posts = Sharded::BlogPost.where(comments: comments.last).to_a

    expected_posts = [sharded_blog_posts(:great_post_blog_two)]
    assert_equal(expected_posts.map(&:id).sort, blog_posts.map(&:id).sort)
  end

  def test_querying_by_relation_with_composite_key
    expected_posts = [sharded_blog_posts(:great_post_blog_one), sharded_blog_posts(:great_post_blog_two)]

    blog_posts = Sharded::BlogPost.where(comments: Sharded::Comment.where(body: "I really enjoyed the post!")).to_a

    assert_equal(expected_posts.map(&:id).sort, blog_posts.map(&:id).sort)
  end

  def test_has_many_association_with_composite_foreign_key_loads_records
    blog_post = sharded_blog_posts(:great_post_blog_one)

    comments = blog_post.comments.to_a
    assert_includes(comments, sharded_comments(:wow_comment_blog_post_one))
    assert_includes(comments, sharded_comments(:great_comment_blog_post_one))
  end

  def test_belongs_to_with_explicit_composite_foreign_key
    car = Cpk::Car.create(make: "Tesla", model: "Model S")
    review = Cpk::CarReview.create(car: car, comment: "Great car!", rating: 5)

    review.reload

    sql = capture_sql do
      assert_equal(car, review.car)
    end

    assert_match(/#{Regexp.escape(quote_table_name("cpk_cars.make"))} =/, sql.first)
    assert_match(/#{Regexp.escape(quote_table_name("cpk_cars.model"))} =/, sql.first)
  end

  def test_cpk_model_has_many_records_by_id_attribute
    order = cpk_orders(:cpk_groceries_order_1)
    _order_shop_id, order_id = order.id
    agreements = 2.times.map { Cpk::OrderAgreement.create(order_id: order_id, signature: "signed") }

    assert_equal(agreements.sort, order.order_agreements.to_a.sort)
  end

  def test_has_many_association_from_a_model_with_query_constraints_different_from_the_association
    blog_post = sharded_blog_posts(:great_post_blog_one)
    blog_post = Sharded::BlogPostWithRevision.find(blog_post.id)
    comments = []
    expected_comments = Sharded::Comment.where(blog_id: blog_post.blog_id, blog_post_id: blog_post.id).to_a

    sql = capture_sql do
      comments = blog_post.comments.to_a
    end.first

    assert_match(/WHERE .*#{Regexp.escape(quote_table_name("sharded_comments.blog_id"))} =/, sql)
    assert_not_empty(comments)
    assert_equal(expected_comments.sort, comments.sort)
  end

  def test_query_constraints_over_three_without_defining_explicit_foreign_key_query_constraints_raises
    Sharded::BlogPostWithRevision.has_many :comments_without_query_constraints, primary_key: [:blog_id, :id], class_name: "Comment"
    blog_post = sharded_blog_posts(:great_post_blog_one)
    blog_post = Sharded::BlogPostWithRevision.find(blog_post.id)

    error = assert_raises ArgumentError do
      blog_post.comments_without_query_constraints.to_a
    end

    assert_equal "The query constraints list on the `Sharded::BlogPostWithRevision` model has more than 2 attributes. Active Record is unable to derive the query constraints for the association. You need to explicitly define the query constraints for this association.", error.message
  end

  def test_model_with_composite_query_constraints_has_many_association_sql
    blog_post = sharded_blog_posts(:great_post_blog_one)

    sql = capture_sql do
      blog_post.comments.to_a
    end.first

    assert_match(/#{Regexp.escape(quote_table_name("sharded_comments.blog_post_id"))} =/, sql)
    assert_match(/#{Regexp.escape(quote_table_name("sharded_comments.blog_id"))} =/, sql)
  end

  def test_belongs_to_association_does_not_use_parent_query_constraints_if_not_configured_to
    comment = sharded_comments(:great_comment_blog_post_one)
    blog_post = Sharded::BlogPost.new(blog_id: comment.blog_id, title: "Following best practices")

    comment.blog_post_by_id = blog_post

    comment.save

    assert_predicate blog_post, :persisted?
    assert_equal(blog_post, comment.blog_post_by_id)
  end

  def test_polymorphic_belongs_to_uses_parent_query_constraints
    parent_post = sharded_blog_posts(:great_post_blog_one)
    child_post = Sharded::BlogPost.create!(title: "Child post", blog_id: parent_post.blog_id, parent: parent_post)
    child_post.reload # reload to forget the parent association

    assert_equal parent_post, child_post.parent
  end

  def test_preloads_model_with_query_constraints_by_explicitly_configured_fk_and_pk
    comment = sharded_comments(:great_comment_blog_post_one)
    comments = Sharded::Comment.where(id: comment.id).preload(:blog_post_by_id).to_a
    comment = comments.first
    assert_equal(comment.blog_post_by_id, comment.blog_post)
  end

  def test_append_composite_foreign_key_has_many_association
    blog_post = sharded_blog_posts(:great_post_blog_one)
    comment = Sharded::Comment.new(body: "Great post! :clap:")
    comment.save
    blog_post.comments << comment

    assert_includes(blog_post.comments, comment)
    assert_equal(blog_post.id, comment.blog_post_id)
    assert_equal(blog_post.blog_id, comment.blog_id)
  end

  def test_nullify_composite_foreign_key_has_many_association
    blog_post = sharded_blog_posts(:great_post_blog_one)
    comment = sharded_comments(:great_comment_blog_post_one)

    assert_not_empty(blog_post.comments)
    blog_post.comments = []

    comment = Sharded::Comment.find(comment.id)
    assert_nil(comment.blog_post_id)
    assert_nil(comment.blog_id)

    assert_empty(blog_post.comments)
    assert_empty(blog_post.reload.comments)
  end

  def test_assign_persisted_composite_foreign_key_belongs_to_association
    comment = sharded_comments(:great_comment_blog_post_one)
    another_blog = sharded_blogs(:sharded_blog_two)
    assert_not_equal(comment.blog_id, another_blog.id)

    blog_post = Sharded::BlogPost.new(title: "New post", blog_id: another_blog.id)
    blog_post.save
    comment.blog_post = blog_post

    assert_equal(blog_post, comment.blog_post)
    assert_equal(comment.blog_id, blog_post.blog_id)
    assert_equal(another_blog.id, comment.blog_id)
    assert_equal(comment.blog_post_id, blog_post.id)
  end

  def test_nullify_composite_foreign_key_belongs_to_association
    comment = sharded_comments(:great_comment_blog_post_one)
    assert_not_nil(comment.blog_post)

    comment.blog_post = nil
    assert_nil(comment.blog_id)
    assert_nil(comment.blog_post_id)

    comment.save
    assert_nil(comment.blog_post)
    assert_nil(comment.reload.blog_post)
  end

  def test_assign_composite_foreign_key_belongs_to_association
    comment = sharded_comments(:great_comment_blog_post_one)
    another_blog = sharded_blogs(:sharded_blog_two)
    assert_not_equal(comment.blog_id, another_blog.id)

    blog_post = Sharded::BlogPost.new(title: "New post", blog_id: another_blog.id)
    comment.blog_post = blog_post

    assert_equal(blog_post, comment.blog_post)
    assert_equal(comment.blog_id, blog_post.blog_id)
    assert_equal(another_blog.id, comment.blog_id)
  end

  def test_query_constraints_that_dont_include_the_primary_key_raise_with_a_single_column
    original = Sharded::BlogPost.instance_variable_get(:@query_constraints_list)
    Sharded::BlogPost.query_constraints :title
    Sharded::BlogPost.has_many :comments_without_single_column_query_constraints, primary_key: [:blog_id, :id], class_name: "Comment"
    blog_post = sharded_blog_posts(:great_post_blog_one)

    error = assert_raises ArgumentError do
      blog_post.comments_without_single_column_query_constraints.to_a
    end

    assert_equal "The query constraints on the `Sharded::BlogPost` model does not include the primary key so Active Record is unable to derive the foreign key constraints for the association. You need to explicitly define the query constraints for this association.", error.message
  ensure
    Sharded::BlogPost.instance_variable_set(:@query_constraints_list, original)
  end

  def test_query_constraints_that_dont_include_the_primary_key_raise_with_multiple_columns
    original = Sharded::BlogPost.instance_variable_get(:@query_constraints_list)
    Sharded::BlogPost.query_constraints :title, :revision
    Sharded::BlogPost.has_many :comments_without_multiple_column_query_constraints, primary_key: [:blog_id, :id], class_name: "Comment"
    blog_post = sharded_blog_posts(:great_post_blog_one)

    error = assert_raises ArgumentError do
      blog_post.comments_without_multiple_column_query_constraints.to_a
    end

    assert_equal "The query constraints on the `Sharded::BlogPost` model does not include the primary key so Active Record is unable to derive the foreign key constraints for the association. You need to explicitly define the query constraints for this association.", error.message
  ensure
    Sharded::BlogPost.instance_variable_set(:@query_constraints_list, original)
  end

  def test_assign_belongs_to_cpk_model_by_id_attribute
    order = cpk_orders(:cpk_groceries_order_1)
    agreement = Cpk::OrderAgreement.new(signature: "signed")

    agreement.order = order
    agreement.save

    assert_not_nil(agreement.reload.order)
    assert_not_nil(agreement.order_id)

    assert_equal(order, agreement.order)
    _shop_id, order_id = order.id
    assert_equal(order_id, agreement.order_id)
  end

  def test_append_composite_foreign_key_has_many_association_with_autosave
    blog_post = sharded_blog_posts(:great_post_blog_one)
    comment = Sharded::Comment.new(body: "Great post! :clap:")
    blog_post.comments << comment

    assert_predicate(comment, :persisted?)
    assert_includes(blog_post.comments, comment)
    assert_equal(blog_post.id, comment.blog_post_id)
    assert_equal(blog_post.blog_id, comment.blog_id)
  end

  def test_assign_composite_foreign_key_belongs_to_association_with_autosave
    comment = sharded_comments(:great_comment_blog_post_one)
    another_blog = sharded_blogs(:sharded_blog_two)
    assert_not_equal(comment.blog_id, another_blog.id)

    blog_post = Sharded::BlogPost.new(title: "New post", blog_id: another_blog.id)
    comment.blog_post = blog_post
    comment.save

    assert_predicate(blog_post, :persisted?)
    assert_equal(blog_post, comment.blog_post)
    assert_equal(comment.blog_id, blog_post.blog_id)
    assert_equal(another_blog.id, comment.blog_id)
    assert_equal(comment.blog_post_id, blog_post.id)
  end

  def test_append_composite_has_many_through_association
    blog_post = sharded_blog_posts(:great_post_blog_one)
    tag = Sharded::Tag.new(name: "Ruby on Rails", blog_id: blog_post.blog_id)
    tag.save

    blog_post.tags << tag

    assert_includes(blog_post.reload.tags, tag)
    assert_predicate Sharded::BlogPostTag.where(blog_post_id: blog_post.id, blog_id: blog_post.blog_id, tag_id: tag.id), :exists?
  end

  def test_append_composite_has_many_through_association_with_autosave
    blog_post = sharded_blog_posts(:great_post_blog_one)
    tag = Sharded::Tag.new(name: "Ruby on Rails", blog_id: blog_post.blog_id)

    blog_post.tags << tag

    assert_includes(blog_post.reload.tags, tag)
    assert_predicate Sharded::BlogPostTag.where(blog_post_id: blog_post.id, blog_id: blog_post.blog_id, tag_id: tag.id), :exists?
  end

  def test_nullify_composite_has_many_through_association
    blog_post = sharded_blog_posts(:great_post_blog_one)
    assert_not_empty(blog_post.tags)

    blog_post.tags = []

    assert_empty(blog_post.tags)
    assert_empty(blog_post.reload.tags)
    assert_not_predicate Sharded::BlogPostTag.where(blog_post_id: blog_post.id, blog_id: blog_post.blog_id), :exists?
  end

  def test_using_query_constraints_warns_about_changing_behavior
    has_many_expected_message = <<~MSG.squish
      Setting `query_constraints:` option on `Sharded::BlogPost.has_many :qc_deprecated_comments` is not allowed.
      To get the same behavior, use the `foreign_key` option instead.
    MSG

    assert_raises(ActiveRecord::ConfigurationError, match: has_many_expected_message) do
      Sharded::BlogPost.has_many :qc_deprecated_comments,
        class_name: "Sharded::Comment", query_constraints: [:blog_id, :blog_post_id]
    end

    belongs_to_expected_message = <<~MSG.squish
      Setting `query_constraints:` option on `Sharded::Comment.belongs_to :qc_deprecated_blog_post` is not allowed.
      To get the same behavior, use the `foreign_key` option instead.
    MSG

    assert_raises(ActiveRecord::ConfigurationError, match: belongs_to_expected_message) do
      Sharded::Comment.belongs_to :qc_deprecated_blog_post,
        class_name: "Sharded::Blog", query_constraints: [:blog_id, :blog_post_id]
    end
  end
end

class AssociationProxyTest < ActiveRecord::TestCase
  fixtures :authors, :author_addresses, :posts, :categorizations, :categories, :developers, :projects, :developers_projects, :members

  def test_push_does_not_load_target
    david = authors(:david)

    david.posts << (post = Post.new(title: "New on Edge", body: "More cool stuff!"))
    assert_not_predicate david.posts, :loaded?
    assert_includes david.posts, post
  end

  def test_push_has_many_through_does_not_load_target
    david = authors(:david)

    david.categories << categories(:technology)
    assert_not_predicate david.categories, :loaded?
    assert_includes david.categories, categories(:technology)
  end

  def test_push_followed_by_save_does_not_load_target
    david = authors(:david)

    david.posts << (post = Post.new(title: "New on Edge", body: "More cool stuff!"))
    assert_not_predicate david.posts, :loaded?
    david.save
    assert_not_predicate david.posts, :loaded?
    assert_includes david.posts, post
  end

  def test_push_does_not_lose_additions_to_new_record
    josh = Author.new(name: "Josh")
    josh.posts << Post.new(title: "New on Edge", body: "More cool stuff!")
    assert_predicate josh.posts, :loaded?
    assert_equal 1, josh.posts.size
  end

  def test_append_behaves_like_push
    josh = Author.new(name: "Josh")
    josh.posts.append Post.new(title: "New on Edge", body: "More cool stuff!")
    assert_predicate josh.posts, :loaded?
    assert_equal 1, josh.posts.size
  end

  def test_prepend_is_not_defined
    josh = Author.new(name: "Josh")
    assert_raises(NoMethodError) { josh.posts.prepend Post.new }
  end

  def test_save_on_parent_does_not_load_target
    david = developers(:david)

    assert_not_predicate david.projects, :loaded?
    david.update_columns(created_at: Time.now)
    assert_not_predicate david.projects, :loaded?
  end

  def test_load_does_load_target
    david = developers(:david)

    assert_not_predicate david.projects, :loaded?
    david.projects.load
    assert_predicate david.projects, :loaded?
  end

  def test_inspect_does_not_reload_a_not_yet_loaded_target
    andreas = Developer.new name: "Andreas", log: "new developer added"
    assert_not_predicate andreas.audit_logs, :loaded?
    assert_match(/message: "new developer added"/, andreas.audit_logs.inspect)
    assert_predicate andreas.audit_logs, :loaded?
  end

  def test_pretty_print_does_not_reload_a_not_yet_loaded_target
    andreas = Developer.new(log: "new developer added")
    assert_not_predicate andreas.audit_logs, :loaded?
    out = StringIO.new
    PP.pp(andreas.audit_logs, out)
    assert_match(/message: "new developer added"/, out.string)
    assert_predicate andreas.audit_logs, :loaded?
  end

  def test_save_on_parent_saves_children
    developer = Developer.create name: "Bryan", salary: 50_000
    assert_equal 1, developer.reload.audit_logs.size
  end

  def test_create_via_association_with_block
    post = authors(:david).posts.create(title: "New on Edge") { |p| p.body = "More cool stuff!" }
    assert_equal "New on Edge", post.title
    assert_equal "More cool stuff!", post.body
  end

  def test_create_with_bang_via_association_with_block
    post = authors(:david).posts.create!(title: "New on Edge") { |p| p.body = "More cool stuff!" }
    assert_equal "New on Edge", post.title
    assert_equal "More cool stuff!", post.body
  end

  def test_reload_returns_association
    david = developers(:david)
    assert_nothing_raised do
      assert_equal david.projects, david.projects.reload.reload
    end
  end

  def test_proxy_association_accessor
    david = developers(:david)
    assert_equal david.association(:projects), david.projects.proxy_association
  end

  def test_scoped_allows_conditions
    assert developers(:david).projects.merge(where: "foo").to_sql.include?("foo")
  end

  test "getting a scope from an association" do
    david = developers(:david)

    assert david.projects.scope.is_a?(ActiveRecord::Relation)
    assert_equal david.projects, david.projects.scope
  end

  test "proxy object is cached" do
    david = developers(:david)
    assert_same david.projects, david.projects
  end

  test "proxy object can be stubbed" do
    david = developers(:david)
    david.projects.define_singleton_method(:extra_method) { 42 }

    assert_equal 42, david.projects.extra_method
  end

  test "inverses get set of subsets of the association" do
    human = Human.create
    human.interests.create

    human = Human.find(human.id)

    assert_queries_count(1) do
      assert_equal human, human.interests.where("1=1").first.human
    end
  end

  test "first! works on loaded associations" do
    david = authors(:david)
    assert_equal david.first_posts.first, david.first_posts.reload.first!
    assert_predicate david.first_posts, :loaded?
    assert_no_queries { david.first_posts.first! }
  end

  def test_pluck_uses_loaded_target
    david = authors(:david)
    assert_equal david.first_posts.pluck(:title), david.first_posts.load.pluck(:title)
    assert_predicate david.first_posts, :loaded?
    assert_no_queries { david.first_posts.pluck(:title) }
  end

  def test_pick_uses_loaded_target
    david = authors(:david)
    assert_equal david.first_posts.pick(:title), david.first_posts.load.pick(:title)
    assert_predicate david.first_posts, :loaded?
    assert_no_queries { david.first_posts.pick(:title) }
  end

  def test_reset_unloads_target
    david = authors(:david)
    david.posts.reload

    assert_predicate david.posts, :loaded?
    assert_predicate david.posts, :loaded
    david.posts.reset
    assert_not_predicate david.posts, :loaded?
    assert_not_predicate david.posts, :loaded
  end

  def test_target_merging_ignores_persisted_in_memory_records
    david = authors(:david)
    assert david.thinking_posts.include?(posts(:thinking))

    david.thinking_posts.create!(title: "Something else entirely", body: "Does not matter.")

    assert_equal 1, david.thinking_posts.size
    assert_equal 1, david.thinking_posts.to_a.size
  end

  def test_target_merging_ignores_persisted_in_memory_records_when_loaded_records_are_empty
    member = members(:blarpy_winkup)
    assert_empty member.favorite_memberships

    membership = member.favorite_memberships.create!
    membership.update!(favorite: false)

    assert_empty member.favorite_memberships.to_a
  end

  def test_target_merging_recognizes_updated_in_memory_records
    member = members(:blarpy_winkup)
    membership = member.create_membership!(favorite: false)

    assert_empty member.favorite_memberships

    membership.update!(favorite: true)

    assert_not_empty member.favorite_memberships.to_a
  end

  def test_size_differentiates_between_new_and_persisted_in_memory_records_when_loaded_records_are_empty
    member = members(:blarpy_winkup)
    assert_empty member.favorite_memberships

    membership = member.favorite_memberships.create!
    membership.update!(favorite: false)

    # CollectionAssociation#size has different behavior when loaded vs. non-loaded
    # the first call will mark the association as loaded and the second call will
    # take a different code path, so it's important to keep both assertions
    assert_equal 0, member.favorite_memberships.size
    assert_equal 0, member.favorite_memberships.size
  end
end

class OverridingAssociationsTest < ActiveRecord::TestCase
  class DifferentPerson < ActiveRecord::Base; end

  class PeopleList < ActiveRecord::Base
    has_and_belongs_to_many :has_and_belongs_to_many, before_add: :enlist
    has_many :has_many, before_add: :enlist
    belongs_to :belongs_to
    has_one :has_one
  end

  class DifferentPeopleList < PeopleList
    # Different association with the same name, callbacks should be omitted here.
    has_and_belongs_to_many :has_and_belongs_to_many, class_name: "DifferentPerson"
    has_many :has_many, class_name: "DifferentPerson"
    belongs_to :belongs_to, class_name: "DifferentPerson"
    has_one :has_one, class_name: "DifferentPerson"
  end

  def test_habtm_association_redefinition_callbacks_should_differ_and_not_inherited
    # redeclared association on AR descendant should not inherit callbacks from superclass
    callbacks = PeopleList.before_add_for_has_and_belongs_to_many
    assert_equal(1, callbacks.length)
    callbacks = DifferentPeopleList.before_add_for_has_and_belongs_to_many
    assert_equal([], callbacks)
  end

  def test_has_many_association_redefinition_callbacks_should_differ_and_not_inherited
    # redeclared association on AR descendant should not inherit callbacks from superclass
    callbacks = PeopleList.before_add_for_has_many
    assert_equal(1, callbacks.length)
    callbacks = DifferentPeopleList.before_add_for_has_many
    assert_equal([], callbacks)
  end

  def test_habtm_association_redefinition_reflections_should_differ_and_not_inherited
    assert_not_equal(
      PeopleList.reflect_on_association(:has_and_belongs_to_many),
      DifferentPeopleList.reflect_on_association(:has_and_belongs_to_many)
    )
  end

  def test_has_many_association_redefinition_reflections_should_differ_and_not_inherited
    assert_not_equal(
      PeopleList.reflect_on_association(:has_many),
      DifferentPeopleList.reflect_on_association(:has_many)
    )
  end

  def test_belongs_to_association_redefinition_reflections_should_differ_and_not_inherited
    assert_not_equal(
      PeopleList.reflect_on_association(:belongs_to),
      DifferentPeopleList.reflect_on_association(:belongs_to)
    )
  end

  def test_has_one_association_redefinition_reflections_should_differ_and_not_inherited
    assert_not_equal(
      PeopleList.reflect_on_association(:has_one),
      DifferentPeopleList.reflect_on_association(:has_one)
    )
  end

  def test_requires_symbol_argument
    assert_raises ArgumentError do
      Class.new(Post) do
        belongs_to "author"
      end
    end
  end

  class ModelAssociatedToClassesThatDoNotExist < ActiveRecord::Base
    self.table_name = "accounts" # this is just to avoid adding a new model just for this test

    has_one :non_existent_has_one_class
    belongs_to :non_existent_belongs_to_class
    has_many :non_existent_has_many_classes
  end

  def test_associations_raise_with_name_error_if_associated_to_classes_that_do_not_exist
    assert_raises NameError do
      ModelAssociatedToClassesThatDoNotExist.new.non_existent_has_one_class
    end

    assert_raises NameError do
      ModelAssociatedToClassesThatDoNotExist.new.non_existent_belongs_to_class
    end

    assert_raises NameError do
      ModelAssociatedToClassesThatDoNotExist.new.non_existent_has_many_classes
    end
  end
end

class PreloaderTest < ActiveRecord::TestCase
  fixtures :posts, :comments, :books, :authors, :tags, :taggings, :essays, :categories, :author_addresses,
           :sharded_blog_posts, :sharded_comments, :sharded_blog_posts_tags, :sharded_tags,
           :members, :member_details, :organizations, :cpk_authors, :cpk_orders, :cpk_books, :cpk_order_agreements,
           :dogs, :other_dogs

  def test_preload_with_scope
    post = posts(:welcome)

    preloader = ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments, scope: Comment.where(body: "Thank you for the welcome"))
    preloader.call

    assert_predicate post.comments, :loaded?
    assert_equal [comments(:greetings)], post.comments
  end

  def test_preloader_association_exposes_lazy_loaded_records
    post = posts(:welcome)
    preloader = ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments)
    loader = preloader.loaders.first

    assert_not_predicate loader, :run?
    assert_equal [post], loader.records_by_owner.keys
    assert_equal post.comments.reload.sort_by(&:id), loader.preloaded_records.sort_by(&:id)
    assert_not_predicate loader, :run?
  end

  def test_preloader_association_exposes_lazy_preloaded_records
    post = posts(:welcome)
    preloader = ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments)
    loader = preloader.loaders.first

    assert_not_predicate loader, :run?
    assert_equal post.comments.reload.sort_by(&:id), loader.preloaded_records.sort_by(&:id)
    assert_equal [post], loader.records_by_owner.keys
    assert_not_predicate loader, :run?
  end

  def test_preload_with_strict_loading_scope_cascades_to_loaded_records
    post = posts(:welcome)

    preloader = ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments, scope: Comment.strict_loading)
    preloader.call

    assert_predicate post.comments.first, :strict_loading?
  end

  def test_preloader_batch_advances_branches_with_no_runnable_loaders
    branch = Struct.new(:children) do
      def runnable_loaders; []; end
      def done?; true; end
    end.new([])
    preloader = Struct.new(:branches) do
      def empty?; false; end
    end.new([branch])

    assert_nothing_raised do
      ActiveRecord::Associations::Preloader::Batch.new([preloader], available_records: []).call
    end
  end

  def test_preloader_batch_loads_all_loaders_when_every_loader_targets_a_future_table
    similar_query = Struct.new(:loaded_batches) do
      def load_records_in_batch(loaders)
        loaded_batches << loaders
      end
    end.new([])
    loader = Struct.new(:klass, :loader_query, :runs, :associated_records, keyword_init: true) do
      def table_name; klass.table_name; end
      def associate_records_from_unscoped(records); associated_records << records; end
      def run; runs << self; end
    end.new(klass: Author, loader_query: similar_query, runs: [], associated_records: [])
    future_author_table = Class.new do
      def self.table_name; Author.table_name; end
    end
    branch = Struct.new(:loader, :future_class, :children) do
      def runnable_loaders; [loader]; end
      def future_classes; [future_class]; end
      def done?; true; end
    end.new(loader, future_author_table, [])
    preloader = Struct.new(:branches) do
      def empty?; false; end
    end.new([branch])

    ActiveRecord::Associations::Preloader::Batch.new([preloader], available_records: []).call

    assert_equal [[loader]], similar_query.loaded_batches
    assert_equal [loader], loader.runs
    assert_equal [nil], loader.associated_records
  end

  def test_preloader_branch_requires_symbol_or_string_association_names
    error = assert_raises(ArgumentError) do
      ActiveRecord::Associations::Preloader::Branch.new(
        association: Object.new,
        children: nil,
        parent: nil,
        associate_by_default: true,
        scope: nil
      )
    end

    assert_match(/Association names must be Symbol or String/, error.message)
  end

  def test_preloader_branch_target_classes_use_preloaded_records_when_done
    branch = ActiveRecord::Associations::Preloader::Branch.new(
      association: nil,
      children: nil,
      parent: nil,
      associate_by_default: true,
      scope: nil
    )
    branch.preloaded_records = [Struct.new(:klass).new(Author), Struct.new(:klass).new(Post)]

    assert_equal [Author, Post], branch.target_classes
  end

  def test_preloader_branch_skips_missing_child_reflections_under_polymorphic_parent
    parent = Struct.new(:preloaded_records) do
      def polymorphic?; true; end
    end.new([authors(:david)])
    branch = ActiveRecord::Associations::Preloader::Branch.new(
      association: :not_an_association,
      children: nil,
      parent: parent,
      associate_by_default: true,
      scope: nil
    )

    assert_empty branch.grouped_records
  end

  def test_preloader_branch_memoizes_polymorphic_detection
    comment = comments(:greetings)
    parent = ActiveRecord::Associations::Preloader::Branch.new(
      association: nil,
      children: nil,
      parent: nil,
      associate_by_default: true,
      scope: nil
    )
    parent.preloaded_records = [comment]
    branch = ActiveRecord::Associations::Preloader::Branch.new(
      association: :origin,
      children: nil,
      parent: parent,
      associate_by_default: true,
      scope: nil
    )

    assert_predicate branch, :polymorphic?
    assert_predicate branch, :polymorphic?
  end

  def test_preloader_through_association_filters_loaded_through_records_by_source_type
    owner = Struct.new(:through_association) do
      def association(name)
        if name == :taggings
          through_association
        else
          Struct.new(:loaded?).new(false)
        end
      end
    end.new(Struct.new(:loaded?).new(true))
    source_record = Struct.new(:id).new(1)
    matching_through = { "source_type" => "Post" }
    skipped_through = { "source_type" => "Comment" }
    reflection = Struct.new(:name, :options, :through_reflection, :foreign_type).new(
      :tagged_posts,
      { source_type: "Post" },
      Struct.new(:name).new(:taggings),
      "source_type"
    )
    loader = ActiveRecord::Associations::Preloader::ThroughAssociation.allocate
    loader.instance_variable_set(:@owners, [owner])
    loader.instance_variable_set(:@reflection, reflection)
    loader.instance_variable_set(:@through_records_by_owner, { owner => [matching_through, skipped_through] })
    loader.instance_variable_set(:@source_records_by_owner, { matching_through => [source_record], skipped_through => [Struct.new(:id).new(2)] })
    loader.instance_variable_set(:@scope, Struct.new(:order_values, :distinct_value).new([], false))

    assert_equal [source_record], loader.records_by_owner[owner]
  end

  def test_preloader_through_association_orders_and_deduplicates_records_by_preload_index
    owner = Struct.new(:loaded_association) do
      def association(*) = loaded_association
    end.new(Struct.new(:loaded?).new(false))
    first_record = Struct.new(:id).new(1)
    second_record = Struct.new(:id).new(2)
    first_through = Object.new
    second_through = Object.new
    reflection = Struct.new(:name, :options, :through_reflection).new(:ordered_tags, {}, Struct.new(:name).new(:taggings))
    loader = ActiveRecord::Associations::Preloader::ThroughAssociation.allocate
    loader.instance_variable_set(:@owners, [owner])
    loader.instance_variable_set(:@reflection, reflection)
    loader.instance_variable_set(:@through_records_by_owner, { owner => [first_through, second_through] })
    loader.instance_variable_set(:@source_records_by_owner, { first_through => [second_record, first_record], second_through => [second_record] })
    loader.instance_variable_set(:@preloaded_records, [first_record, second_record])
    loader.instance_variable_set(:@scope, Struct.new(:order_values, :distinct_value).new([Arel.sql("tags.id")], true))

    assert_equal [first_record, second_record], loader.records_by_owner[owner]
  end

  def test_preloader_through_scope_applies_join_scope_values
    loader = ActiveRecord::Associations::Preloader::ThroughAssociation.allocate
    through_reflection = Struct.new(:klass).new(Tagging)
    source_reflection = Struct.new(:name, :table_name).new(:tag, Tag.table_name)
    reflection = Struct.new(:options, :through_reflection, :source_reflection).new({}, through_reflection, source_reflection)
    reflection_scope = Tagging.annotate("preloader annotation").includes(:tag).references(:tags).joins(:tag).left_outer_joins(:tag).where(tags: { name: "Blue" }).order("tags.name")
    loader.instance_variable_set(:@reflection, reflection)
    loader.instance_variable_set(:@reflection_scope, reflection_scope)
    loader.instance_variable_set(:@preload_scope, nil)

    through_scope = loader.__send__(:through_scope)

    assert_includes through_scope.values[:annotate], "preloader annotation"
    assert_equal [{ tag: [:tag] }], through_scope.values[:includes]
    assert_includes through_scope.references_values, "tags"
    assert_equal [{ tag: [:tag] }], through_scope.joins_values
    assert_equal [{ tag: [:tag] }], through_scope.left_outer_joins_values
    assert_equal ["tags.name"], through_scope.order_values
  end

  def test_preloader_through_scope_handles_disable_joins_and_source_type
    disable_loader = ActiveRecord::Associations::Preloader::ThroughAssociation.allocate
    through_reflection = Struct.new(:klass).new(Tagging)
    source_reflection = Struct.new(:name, :table_name).new(:tag, Tag.table_name)
    disable_loader.instance_variable_set(:@reflection, Struct.new(:options, :through_reflection, :source_reflection).new({ disable_joins: true }, through_reflection, source_reflection))

    assert_empty disable_loader.__send__(:through_scope).where_clause

    source_type_loader = ActiveRecord::Associations::Preloader::ThroughAssociation.allocate
    reflection = Struct.new(:options, :through_reflection, :source_reflection, :foreign_type).new({ source_type: "Post" }, through_reflection, source_reflection, "taggable_type")
    source_type_loader.instance_variable_set(:@reflection, reflection)
    source_type_loader.instance_variable_set(:@preload_scope, nil)
    source_type_loader.instance_variable_set(:@reflection_scope, Tagging.all)

    assert_match(/#{Regexp.escape(quote_table_name("taggings.taggable_type"))} = 'Post'/, source_type_loader.__send__(:through_scope).to_sql)
  end

  def test_preload_makes_correct_number_of_queries_on_array
    post = posts(:welcome)

    assert_queries_count(1) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments)
      preloader.call
    end
  end

  def test_preload_makes_correct_number_of_queries_on_relation
    post = posts(:welcome)
    relation = Post.where(id: post.id)

    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: relation, associations: :comments)
      preloader.call
    end
  end

  def test_preload_does_not_concatenate_duplicate_records
    post = posts(:welcome)
    post.reload
    post.comments.create!(body: "A new comment")

    ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments).call

    assert_equal post.comments.length, post.comments.count
    assert_equal post.comments.all.to_a, post.comments
  end

  def test_preload_for_hmt_with_conditions
    post = posts(:welcome)
    _normal_category = post.categories.create!(name: "Normal")
    special_category = post.special_categories.create!(name: "Special")

    preloader = ActiveRecord::Associations::Preloader.new(records: [post], associations: :hmt_special_categories)
    preloader.call

    assert_equal 1, post.hmt_special_categories.length
    assert_equal [special_category], post.hmt_special_categories
  end

  def test_preload_groups_queries_with_same_scope
    book = books(:awdr)
    post = posts(:welcome)

    assert_queries_count(1) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [book, post], associations: :author)
      preloader.call
    end

    assert_no_queries do
      book.author
      post.author
    end
  end

  def test_preload_grouped_queries_with_already_loaded_records
    book = books(:awdr)
    post = posts(:welcome)
    book.author

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [book, post], associations: :author).call
      book.author
      post.author
    end
  end

  def test_preload_grouped_queries_of_middle_records
    comments = [
      comments(:eager_sti_on_associations_s_comment1),
      comments(:eager_sti_on_associations_s_comment2),
    ]

    assert_queries_count(2) do
      ActiveRecord::Associations::Preloader.new(records: comments, associations: [:author, :ordinary_post]).call
    end
  end

  def test_preload_grouped_queries_of_through_records
    author = authors(:david)

    assert_queries_count(3) do
      ActiveRecord::Associations::Preloader.new(records: [author], associations: [:hello_post_comments, :comments]).call
    end
  end

  def test_preload_through_records_with_already_loaded_middle_record
    member = members(:groucho)
    expected_member_detail_ids = member.organization_member_details_2.pluck(:id)

    member.reload.organization # load through record

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [member], associations: :organization_member_details_2).call
    end

    assert_no_queries do
      assert_equal expected_member_detail_ids.sort, member.organization_member_details_2.map(&:id).sort
    end
  end

  def test_preload_with_instance_dependent_scope
    david = authors(:david)
    david2 = Author.create!(name: "David")
    bob = authors(:bob)
    post = Post.create!(
      author: david,
      title: "test post",
      body: "this post is about David"
    )
    post2 = Post.create!(
      author: david,
      title: "test post 2",
      body: "this post is also about David"
    )

    loaders = nil
    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [david, david2, bob], associations: :posts_mentioning_author)
      loaders = preloader.call
    end

    assert_equal 2, loaders.size

    assert_predicate david.posts_mentioning_author, :loaded?
    assert_predicate david2.posts_mentioning_author, :loaded?
    assert_predicate bob.posts_mentioning_author, :loaded?

    assert_equal [post, post2].sort, david.posts_mentioning_author.sort
    assert_equal [], david2.posts_mentioning_author
    assert_equal [], bob.posts_mentioning_author
  end

  def test_preload_with_instance_dependent_through_scope
    david = authors(:david)
    david2 = Author.create!(name: "David")
    bob = authors(:bob)
    comment1 = david.posts.first.comments.create!(body: "Hi David!")
    comment2 = david.posts.first.comments.create!(body: "This comment mentions david")

    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [david, david2, bob], associations: :comments_mentioning_author)
      preloader.call
    end

    assert_predicate david.comments_mentioning_author, :loaded?
    assert_predicate david2.comments_mentioning_author, :loaded?
    assert_predicate bob.comments_mentioning_author, :loaded?

    assert_equal [comment1, comment2].sort, david.comments_mentioning_author.sort
    assert_equal [], david2.comments_mentioning_author
    assert_equal [], bob.comments_mentioning_author
  end

  def test_preload_with_through_instance_dependent_scope
    david = authors(:david)
    david2 = Author.create!(name: "David")
    bob = authors(:bob)
    post = Post.create!(
      author: david,
      title: "test post",
      body: "this post is about David"
    )
    Post.create!(
      author: david,
      title: "test post 2",
      body: "this post is also about David"
    )
    post3 = Post.create!(
      author: bob,
      title: "test post 3",
      body: "this post is about Bob"
    )
    comment1 = post.comments.create!(body: "hi!")
    comment2 = post.comments.create!(body: "hello!")
    comment3 = post3.comments.create!(body: "HI BOB!")

    assert_queries_count(3) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [david, david2, bob], associations: :comments_on_posts_mentioning_author)
      preloader.call
    end

    assert_predicate david.comments_on_posts_mentioning_author, :loaded?
    assert_predicate david2.comments_on_posts_mentioning_author, :loaded?
    assert_predicate bob.comments_on_posts_mentioning_author, :loaded?

    assert_equal [comment1, comment2].sort, david.comments_on_posts_mentioning_author.sort
    assert_equal [], david2.comments_on_posts_mentioning_author
    assert_equal [comment3], bob.comments_on_posts_mentioning_author
  end

  def test_some_already_loaded_associations
    item_discount = Discount.create(amount: 5)
    shipping_discount = Discount.create(amount: 20)

    invoice = Invoice.new
    line_item = LineItem.new(amount: 20)
    line_item.discount_applications << LineItemDiscountApplication.new(discount: item_discount)
    invoice.line_items << line_item

    shipping_line = ShippingLine.new(amount: 50)
    shipping_line.discount_applications << ShippingLineDiscountApplication.new(discount: shipping_discount)
    invoice.shipping_lines << shipping_line

    invoice.save!
    invoice.reload

    # SELECT "line_items".* FROM "line_items" WHERE "line_items"."invoice_id" = ?
    # SELECT "shipping_lines".* FROM shipping_lines WHERE "shipping_lines"."invoice_id" = ?
    # SELECT "line_item_discount_applications".* FROM "line_item_discount_applications" WHERE "line_item_discount_applications"."line_item_id" = ?
    # SELECT "shipping_line_discount_applications".* FROM "shipping_line_discount_applications" WHERE "shipping_line_discount_applications"."shipping_line_id" = ?
    # SELECT "discounts".* FROM "discounts" WHERE "discounts"."id" IN (?, ?).
    assert_queries_count(5) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [invoice], associations: [
        line_items: { discount_applications: :discount },
        shipping_lines: { discount_applications: :discount },
      ])
      preloader.call
    end

    assert_no_queries do
      assert_not_nil invoice.line_items.first.discount_applications.first.discount
      assert_not_nil invoice.shipping_lines.first.discount_applications.first.discount
    end

    invoice.reload
    invoice.line_items.map { |i| i.discount_applications.to_a }
    # `line_items` and `line_item_discount_applications` are already preloaded, so we expect:
    # SELECT "shipping_lines".* FROM shipping_lines WHERE "shipping_lines"."invoice_id" = ?
    # SELECT "shipping_line_discount_applications".* FROM "shipping_line_discount_applications" WHERE "shipping_line_discount_applications"."shipping_line_id" = ?
    # SELECT "discounts".* FROM "discounts" WHERE "discounts"."id" = ?.
    assert_queries_count(3) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [invoice], associations: [
        line_items: { discount_applications: :discount },
        shipping_lines: { discount_applications: :discount },
      ])
      preloader.call
    end

    assert_no_queries do
      assert_not_nil invoice.line_items.first.discount_applications.first.discount
      assert_not_nil invoice.shipping_lines.first.discount_applications.first.discount
    end
  end

  def test_preload_through
    comments = [
      comments(:eager_sti_on_associations_s_comment1),
      comments(:eager_sti_on_associations_s_comment2),
    ]

    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: comments, associations: [:author, :post])
      preloader.call
    end

    assert_no_queries do
      comments.each(&:author)
    end
  end

  def test_preload_groups_queries_with_same_scope_at_second_level
    author = nil

    # Expected
    #   SELECT FROM authors ...
    #   SELECT FROM posts ... (thinking)
    #   SELECT FROM posts ... (welcome)
    #   SELECT FROM comments ... (comments for both welcome and thinking)
    assert_queries_count(4) do
      author = Author
        .where(name: "David")
        .includes(thinking_posts: :comments, welcome_posts: :comments)
        .first
    end

    assert_no_queries do
      author.thinking_posts.map(&:comments)
      author.welcome_posts.map(&:comments)
    end
  end

  def test_preload_groups_queries_with_same_sql_at_second_level
    author = nil

    # Expected
    #   SELECT FROM authors ...
    #   SELECT FROM posts ... (thinking)
    #   SELECT FROM posts ... (welcome)
    #   SELECT FROM comments ... (comments for both welcome and thinking)
    assert_queries_count(4) do
      author = Author
        .where(name: "David")
        .includes(thinking_posts: :comments, welcome_posts: :comments_with_extending)
        .first
    end

    assert_no_queries do
      author.thinking_posts.map(&:comments)
      author.welcome_posts.map(&:comments_with_extending)
    end
  end

  def test_preload_with_grouping_sets_inverse_association
    mary = authors(:mary)
    bob = authors(:bob)

    AuthorFavorite.create!(author: mary, favorite_author: bob)
    favorites = AuthorFavorite.all.load

    assert_queries_count(1) do
      preloader = ActiveRecord::Associations::Preloader.new(records: favorites, associations: [:author, :favorite_author])
      preloader.call
    end

    assert_no_queries do
      favorites.first.author
      favorites.first.favorite_author
    end
  end

  def test_preload_can_group_separate_levels
    mary = authors(:mary)
    bob = authors(:bob)

    AuthorFavorite.create!(author: mary, favorite_author: bob)

    assert_queries_count(3) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [mary], associations: [:posts, favorite_authors: :posts])
      preloader.call
    end

    assert_no_queries do
      mary.posts
      mary.favorite_authors.map(&:posts)
    end
  end

  def test_preload_can_group_multi_level_ping_pong_through
    mary = authors(:mary)
    bob = authors(:bob)

    AuthorFavorite.create!(author: mary, favorite_author: bob)

    associations = { similar_posts: :comments, favorite_authors: { similar_posts: :comments } }

    assert_queries_count(9) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [mary], associations: associations)
      preloader.call
    end

    assert_no_queries do
      mary.similar_posts.map(&:comments).each(&:to_a)
      mary.favorite_authors.flat_map(&:similar_posts).map(&:comments).each(&:to_a)
    end

    # Preloading with automatic scope inversing reduces the number of queries
    tag_reflection = Tagging.reflect_on_association(:tag)
    taggings_reflection = Tag.reflect_on_association(:taggings)

    assert tag_reflection.scope
    assert_not taggings_reflection.scope

    with_automatic_scope_inversing(tag_reflection, taggings_reflection) do
      mary.reload

      assert_queries_count(8) do
        preloader = ActiveRecord::Associations::Preloader.new(records: [mary], associations: associations)
        preloader.call
      end
    end
  end

  def test_preload_does_not_group_same_class_different_scope
    post = posts(:welcome)
    postesque = Postesque.create(author: Author.last)
    postesque.reload

    # When the scopes differ in the generated SQL:
    # SELECT "authors".* FROM "authors" WHERE (name LIKE '%a%') AND "authors"."id" = ?
    # SELECT "authors".* FROM "authors" WHERE "authors"."id" = ?.
    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [post, postesque], associations: :author_with_the_letter_a)
      preloader.call
    end

    assert_no_queries do
      post.author_with_the_letter_a
      postesque.author_with_the_letter_a
    end

    post.reload
    postesque.reload

    # When the generated SQL is identical, but one scope has preload values.
    assert_queries_count(3) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [post, postesque], associations: :author_with_address)
      preloader.call
    end

    assert_no_queries do
      post.author_with_address
      postesque.author_with_address
    end
  end

  def test_preload_does_not_group_same_scope_different_key_name
    post = posts(:welcome)
    postesque = Postesque.create(author: Author.last)
    postesque.reload

    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [post, postesque], associations: :author)
      preloader.call
    end

    assert_no_queries do
      post.author
      postesque.author
    end
  end

  def test_multi_database_polymorphic_preload_with_same_table_name
    dog = dogs(:sophie)
    dog_comment = comments(:greetings)
    dog_comment.origin_type = dog.class.name
    dog_comment.origin_id = dog.id

    other_dog = other_dogs(:lassie)
    other_dog_comment = comments(:more_greetings)
    other_dog_comment.origin_type = other_dog.class.name
    other_dog_comment.origin_id = other_dog.id

    # Both Dog and OtherDog are backed by a table named `dogs`,
    # however they are stored in different databases and should
    # therefore result in two separate queries rather than be batched
    # together.
    #
    # Expected
    #   SELECT FROM dogs ... (Dog)
    #   SELECT FROM dogs ... (OtherDog)
    assert_queries_count(2) do
      preloader = ActiveRecord::Associations::Preloader.new(records: [dog_comment, other_dog_comment], associations: :origin)
      preloader.call
    end
  end

  def test_preload_with_available_records
    post = posts(:welcome)
    david = authors(:david)

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author, available_records: [[david]]).call

      assert_predicate post.association(:author), :loaded?
      assert_same david, post.author
    end
  end

  def test_preload_with_available_record_shared_by_multiple_owners
    david = authors(:david)
    first_post = posts(:welcome)
    second_post = posts(:thinking)
    second_post.update!(author: david)

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [first_post, second_post], associations: :author, available_records: [david]).call

      assert_same david, first_post.author
      assert_same david, second_post.author
    end
  end

  def test_preload_with_available_records_queries_when_association_has_scope
    post = posts(:welcome)
    david = authors(:david)

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author_with_the_letter_a, available_records: [david]).call
    end

    assert_predicate post.association(:author_with_the_letter_a), :loaded?
  end

  def test_preload_with_available_records_sti
    book = Book.create!
    essay_special = EssaySpecial.create!
    book.essay = essay_special
    book.save!
    book.reload

    assert_not_predicate book.association(:essay), :loaded?

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [book], associations: :essay, available_records: [[essay_special]]).call
    end

    assert_predicate book.association(:essay), :loaded?
    assert_same essay_special, book.essay
  end

  def test_preload_with_only_some_records_available
    bob_post = posts(:misc_by_bob)
    mary_post = posts(:misc_by_mary)
    bob = authors(:bob)
    mary = authors(:mary)

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [bob_post, mary_post], associations: :author, available_records: [bob]).call
    end

    assert_no_queries do
      assert_same bob, bob_post.author
      assert_equal mary, mary_post.author
    end
  end

  def test_preload_with_some_records_already_loaded
    bob_post = posts(:misc_by_bob)
    mary_post = posts(:misc_by_mary)
    bob = bob_post.author
    mary = authors(:mary)

    assert_predicate bob_post.association(:author), :loaded?
    assert_not mary_post.association(:author).loaded?

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [bob_post, mary_post], associations: :author).call
    end

    assert_no_queries do
      assert_same bob, bob_post.author
      assert_equal mary, mary_post.author
    end
  end

  def test_preload_with_available_records_with_through_association
    author = authors(:david)
    categories = Category.all.to_a

    assert_queries_count(1) do
      # One query to get the middle records (i.e. essays)
      ActiveRecord::Associations::Preloader.new(records: [author], associations: :essay_category, available_records: categories).call
    end

    assert_predicate author.association(:essay_category), :loaded?
    assert categories.map(&:__id__).include?(author.essay_category.__id__)
  end

  def test_preload_with_only_some_records_available_with_through_associations
    mary = authors(:mary)
    mary_essay = essays(:mary_stay_home)
    mary_category = categories(:technology)
    mary_essay.update!(category: mary_category)

    dave = authors(:david)
    dave_category = categories(:general)

    assert_queries_count(2) do
      ActiveRecord::Associations::Preloader.new(records: [mary, dave], associations: :essay_category, available_records: [mary_category]).call
    end

    assert_no_queries do
      assert_same mary_category, mary.essay_category
      assert_equal dave_category, dave.essay_category
    end
  end

  def test_preload_with_available_records_with_multiple_classes
    essay = essays(:david_modest_proposal)
    general = categories(:general)
    david = authors(:david)

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [essay], associations: [:category, :author], available_records: [general, david]).call

      assert_predicate essay.association(:category), :loaded?
      assert_predicate essay.association(:author), :loaded?
      assert_same general, essay.category
      assert_same david, essay.author
    end
  end

  def test_preload_with_available_records_queries_when_scoped
    post = posts(:welcome)
    david = authors(:david)

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author, scope: Author.where(name: "David"), available_records: [david]).call
    end

    assert_predicate post.association(:author), :loaded?
    assert_not_equal david.__id__, post.author.__id__
  end

  def test_preload_with_available_records_queries_when_collection
    post = posts(:welcome)
    comments = Comment.all.to_a

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments, available_records: comments).call
    end

    assert_predicate post.association(:comments), :loaded?
    assert_empty post.comments.map(&:__id__) & comments.map(&:__id__)
  end

  def test_preload_with_available_records_queries_when_incomplete
    post = posts(:welcome)
    bob = authors(:bob)
    david = authors(:david)

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author, available_records: [bob]).call
    end

    assert_no_queries do
      assert_predicate post.association(:author), :loaded?
      assert_equal david, post.author
    end
  end

  def test_preload_with_unpersisted_records_no_ops
    author = Author.new
    new_post_with_author = Post.new(author: author)
    new_post_without_author = Post.new
    posts = [new_post_with_author, new_post_without_author]

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: posts, associations: :author).call

      assert_same author, new_post_with_author.author
      assert_nil new_post_without_author.author
    end
  end

  def test_preload_with_unpersisted_records_with_composite_foreign_key_no_ops
    order = Cpk::Order.new
    new_book_with_order = Cpk::Book.new(order: order)
    new_book_without_order = Cpk::Book.new
    books = [new_book_with_order, new_book_without_order]

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: books, associations: :order).call

      assert_same order, new_book_with_order.order
      assert_nil new_book_without_order.order
    end
  end

  def test_preload_wont_set_the_wrong_target
    post = posts(:welcome)
    post.update!(author_id: 54321)
    some_other_record = categories(:general)
    some_other_record.update!(id: 54321)

    assert_raises do
      some_other_record.association(:author)
    end

    assert_nothing_raised do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author, available_records: [[some_other_record]]).call
      assert_predicate post.association(:author), :loaded?
      assert_not_equal some_other_record, post.author
    end
  end

  def test_preload_has_many_association_with_composite_foreign_key
    blog_post = sharded_blog_posts(:great_post_blog_one)
    blog_posts = [blog_post, sharded_blog_posts(:great_post_blog_two)]

    ::ActiveRecord::Associations::Preloader.new(records: blog_posts, associations: [:comments]).call

    assert_predicate blog_post.association(:comments), :loaded?
    assert_includes(blog_post.comments.to_a, sharded_comments(:great_comment_blog_post_one))
  end

  def test_preload_belongs_to_association_with_composite_foreign_key
    comment = sharded_comments(:great_comment_blog_post_one)
    comments = [comment, sharded_comments(:great_comment_blog_post_two)]

    ActiveRecord::Associations::Preloader.new(records: comments, associations: :blog_post).call

    assert_predicate comment.association(:blog_post), :loaded?
    assert_equal sharded_blog_posts(:great_post_blog_one), comment.blog_post
  end

  def test_preload_loaded_belongs_to_association_with_composite_foreign_key
    comment = sharded_comments(:great_comment_blog_post_one)
    comment.blog_post

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [comment], associations: :blog_post).call
    end
  end

  def test_preload_has_many_through_association_with_composite_query_constraints
    tag = sharded_tags(:short_read_blog_one)

    tags = [tag, sharded_tags(:breaking_news_blog_2)]

    ActiveRecord::Associations::Preloader.new(records: tags, associations: :blog_posts).call

    assert tags.all? { |tag| tag.association(:blog_posts).loaded? }

    expected_blog_post_ids = Sharded::BlogPostTag
      .where(blog_id: tag.blog_id, tag_id: tag.id)
      .pluck(:blog_post_id)

    assert_not_empty(expected_blog_post_ids)

    assert_equal(expected_blog_post_ids.sort, tag.blog_posts.map(&:id).sort)
  end

  def test_preloads_has_many_on_model_with_a_composite_primary_key_through_id_attribute
    order = cpk_orders(:cpk_groceries_order_2)
    _shop_id, order_id = order.id
    order_agreements = Cpk::OrderAgreement.where(order_id: order_id).to_a

    assert_not_empty order_agreements
    assert_equal order_agreements.sort, order.order_agreements.sort

    loaded_order = nil
    sql = capture_sql do
      loaded_order = Cpk::Order.where(id: order_id).includes(:order_agreements).to_a.first
    end

    assert_equal 2, sql.size
    preload_sql = sql.last

    order_id_column = Regexp.escape(quote_table_name("cpk_order_agreements.order_id"))
    expectation = /SELECT.*WHERE.* #{order_id_column} = (\?|(\d+)|\$\d)$/

    assert_match(expectation, preload_sql)
    assert_equal order_agreements.sort, loaded_order.order_agreements.sort
  end

  def test_preloads_belongs_to_a_composite_primary_key_model_through_id_attribute
    order_agreement = cpk_order_agreements(:order_agreement_three)
    order = cpk_orders(:cpk_groceries_order_2)
    assert_equal order, order_agreement.order

    loaded_order_agreement = nil
    sql = capture_sql do
      loaded_order_agreement = Cpk::OrderAgreement.where(id: order_agreement.id).includes(:order).to_a.first
    end

    assert_equal 2, sql.size
    preload_sql = sql.last

    order_id = Regexp.escape(quote_table_name("cpk_orders.id"))
    expectation = /SELECT.*WHERE.* #{order_id} = (\?|(\d+)|\$\d)$/

    assert_match(expectation, preload_sql)
    assert_equal order, loaded_order_agreement.order
  end

  def test_preload_keeps_built_has_many_records_no_ops
    post = Post.new
    comment = post.comments.build

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments).call

      assert_equal [comment], post.comments.to_a
    end
  end

  def test_preload_keeps_built_has_many_records_with_composite_key_no_ops
    order = Cpk::Order.new
    book = order.books.build

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [order], associations: :books).call

      assert_equal [book], order.books.to_a
    end
  end

  def test_preload_keeps_built_has_many_records_after_query
    post = posts(:welcome)
    comment = post.comments.build

    assert_queries_count(1) do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :comments).call

      assert_includes post.comments.to_a, comment
    end
  end


  def test_preload_keeps_built_belongs_to_records_no_ops
    post = Post.new
    author = post.build_author

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author).call

      assert_same author, post.author
    end
  end

  def test_preload_keeps_built_belongs_to_records_after_query
    post = posts(:welcome)
    author = post.build_author

    assert_no_queries do
      ActiveRecord::Associations::Preloader.new(records: [post], associations: :author).call

      assert_same author, post.author
    end
  end

  def test_preload_group_with_klass
    published_author = PublishedAuthor.create!(name: "PublishedAuthor")
    PublishedBook.create!(name: "PublishedBook", author_id: published_author.id, isbn: "12345")

    author = Author.create!(name: "Author", published_author_id: published_author.id)
    Book.create!(name: "Book", author_id: author.id, isbn: "67890")

    result = Author.includes(books: [], published_author: { books: [] }).last
    assert_equal [PublishedBook], result.published_author.books.map(&:class)
  end
end

class GeneratedMethodsTest < ActiveRecord::TestCase
  fixtures :developers, :computers, :posts, :comments

  def test_association_methods_override_attribute_methods_of_same_name
    assert_equal(developers(:david), computers(:workstation).developer)
    # this next line will fail if the attribute methods module is generated lazily
    # after the association methods module is generated
    assert_equal(developers(:david), computers(:workstation).developer)
    assert_equal(developers(:david).id, computers(:workstation)[:developer])
  end

  def test_model_method_overrides_association_method
    assert_equal(comments(:greetings).body, posts(:welcome).first_comment)
  end

  module MyModule
    def comments; :none end
  end

  class MyArticle < ActiveRecord::Base
    self.table_name = "articles"
    include MyModule
    has_many :comments, inverse_of: false
  end

  def test_included_module_overwrites_association_methods
    assert_equal :none, MyArticle.new.comments
  end
end

class WithAnnotationsTest < ActiveRecord::TestCase
  fixtures :pirates, :parrots, :parrots_pirates, :pirates, :treasures

  def test_belongs_to_with_annotation_includes_a_query_comment
    pirate = SpacePirate.where.not(parrot_id: nil).first
    assert pirate, "should have a Pirate record"

    log = capture_sql do
      pirate.parrot
    end
    assert_not_predicate log, :empty?
    assert_predicate log.select { |query| query.match?(%r{/\*}) }, :empty?

    assert_queries_match(%r{/\* that tells jokes \*/}) do
      pirate.parrot_with_annotation
    end
  end

  def test_has_and_belongs_to_many_with_annotation_includes_a_query_comment
    pirate = SpacePirate.first
    assert pirate, "should have a Pirate record"

    log = capture_sql do
      pirate.parrots.first
    end
    assert_not_predicate log, :empty?
    assert_predicate log.select { |query| query.match?(%r{/\*}) }, :empty?

    assert_queries_match(%r{/\* that are very colorful \*/}) do
      pirate.parrots_with_annotation.first
    end
  end

  def test_has_one_with_annotation_includes_a_query_comment
    pirate = SpacePirate.first
    assert pirate, "should have a Pirate record"

    log = capture_sql do
      pirate.ship
    end
    assert_not_predicate log, :empty?
    assert_predicate log.select { |query| query.match?(%r{/\*}) }, :empty?

    assert_queries_match(%r{/\* that is a rocket \*/}) do
      pirate.ship_with_annotation
    end
  end

  def test_has_many_with_annotation_includes_a_query_comment
    pirate = SpacePirate.first
    assert pirate, "should have a Pirate record"

    log = capture_sql do
      pirate.birds.first
    end
    assert_not_predicate log, :empty?
    assert_predicate log.select { |query| query.match?(%r{/\*}) }, :empty?

    assert_queries_match(%r{/\* that are also parrots \*/}) do
      pirate.birds_with_annotation.first
    end
  end

  def test_has_many_through_with_annotation_includes_a_query_comment
    pirate = SpacePirate.first
    assert pirate, "should have a Pirate record"

    log = capture_sql do
      pirate.treasure_estimates.first
    end
    assert_not_predicate log, :empty?
    assert_predicate log.select { |query| query.match?(%r{/\*}) }, :empty?

    assert_queries_match(%r{/\* yarrr \*/}) do
      pirate.treasure_estimates_with_annotation.first
    end
  end

  def test_has_many_through_with_annotation_includes_a_query_comment_when_eager_loading
    pirate = SpacePirate.first
    assert pirate, "should have a Pirate record"

    log = capture_sql do
      pirate.treasure_estimates.first
    end
    assert_not_predicate log, :empty?
    assert_predicate log.select { |query| query.match?(%r{/\*}) }, :empty?

    assert_queries_match(%r{/\* yarrr \*/}) do
      SpacePirate.includes(:treasure_estimates_with_annotation, :treasures).first
    end
  end

end
