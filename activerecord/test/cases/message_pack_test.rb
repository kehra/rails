# frozen_string_literal: true

require "cases/helper"
require "models/author"
require "models/binary"
require "models/comment"
require "models/post"
require "active_support/message_pack"
require "active_record/message_pack"

class ActiveRecordMessagePackTest < ActiveRecord::TestCase
  fixtures :posts, :comments, :authors, :author_addresses

  test "enshrines type IDs" do
    expected = {
      119 => ActiveModel::Type::Binary::Data,
      120 => ActiveRecord::Base,
    }

    factory = ::MessagePack::Factory.new
    ActiveRecord::MessagePack::Extensions.install(factory)
    actual = factory.registered_types.to_h do |entry|
      [entry[:type], entry[:class]]
    end

    assert_equal expected, actual
  end

  test "roundtrips record and cached associations" do
    post = Post.create!(title: "A Title", body: "A body.")
    post.create_author!(name: "An Author")
    post.comments.create!(body: "A comment.")
    post.comments.create!(body: "Another comment.", author: post.author)
    post.comments.load

    assert_no_queries do
      roundtripped_post = roundtrip(post)

      assert_equal post, roundtripped_post
      assert_equal post.author, roundtripped_post.author
      assert_equal post.comments.to_a, roundtripped_post.comments.to_a
      assert_equal post.comments.map(&:author), roundtripped_post.comments.map(&:author)

      assert_same roundtripped_post, roundtripped_post.comments[0].post
      assert_same roundtripped_post, roundtripped_post.comments[1].post
      assert_same roundtripped_post.author, roundtripped_post.comments[1].author
    end
  end

  test "roundtrips new_record? status" do
    post = Post.new(title: "A Title", body: "A body.")
    post.create_author!(name: "An Author")

    assert_no_queries do
      roundtripped_post = roundtrip(post)

      assert_equal post.attributes, roundtripped_post.attributes
      assert_equal post.new_record?, roundtripped_post.new_record?
      assert_equal post.author, roundtripped_post.author
      assert_equal post.author.new_record?, roundtripped_post.author.new_record?
    end
  end

  test "roundtrips binary attribute" do
    binary = Binary.new(data: Marshal.dump("data"))
    assert_equal binary.attributes, roundtrip(binary).attributes
  end

  test "roundtrips arrays and nil through top-level message pack helpers" do
    posts = [Post.create!(title: "A Title", body: "A body."), Post.create!(title: "Another", body: "body.")]

    roundtripped_posts = ActiveRecord::MessagePack.load(ActiveRecord::MessagePack.dump(posts))
    roundtripped_nil = ActiveRecord::MessagePack.load(ActiveRecord::MessagePack.dump(nil))

    assert_equal posts, roundtripped_posts
    assert_nil roundtripped_nil
  end

  test "raises when message pack format version is unknown" do
    error = assert_raises RuntimeError do
      ActiveRecord::MessagePack.load([999, nil, []])
    end

    assert_equal "Invalid format version: 999", error.message
  end

  test "roundtrips record with no cached association entries" do
    post = Post.create!(title: "A Title", body: "A body.")

    assert_no_queries do
      assert_equal post, ActiveRecord::MessagePack.load(ActiveRecord::MessagePack.dump(post))
    end
  end

  test "skips cached associations that no longer exist" do
    post = Post.create!(title: "A Title", body: "A body.")
    encoded = ActiveRecord::MessagePack.dump(post)
    encoded[2][0] << :legacy_author << nil

    assert_nothing_raised do
      assert_equal post, ActiveRecord::MessagePack.load(encoded)
    end
  end

  test "raises ActiveSupport::MessagePack::MissingClassError if record class no longer exists" do
    klass = Class.new(Post)
    def klass.name; "SomeLegacyClass"; end
    dumped = serializer.dump(klass.new(title: "A Title", body: "A body."))

    assert_raises ActiveSupport::MessagePack::MissingClassError do
      serializer.load(dumped)
    end
  end

  private
    def serializer
      @serializer ||= ::MessagePack::Factory.new.tap do |factory|
        ActiveRecord::MessagePack::Extensions.install(factory)
        ActiveSupport::MessagePack::Extensions.install(factory)
        ActiveSupport::MessagePack::Extensions.install_unregistered_type_error(factory)
      end
    end

    def roundtrip(input)
      serializer.load(serializer.dump(input))
    end
end
