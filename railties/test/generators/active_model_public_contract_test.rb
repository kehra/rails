# frozen_string_literal: true

require "abstract_unit"
require "rails/generators/active_model"

class ActiveModelGeneratorPublicContractTest < ActiveSupport::TestCase
  test "class methods render collection, lookup, and build expressions" do
    assert_equal "Post.all", Rails::Generators::ActiveModel.all("Post")
    assert_equal "Post.find(params[:id])", Rails::Generators::ActiveModel.find("Post", "params[:id]")
    assert_equal "Post.new", Rails::Generators::ActiveModel.build("Post")
    assert_equal "Post.new(post_params)", Rails::Generators::ActiveModel.build("Post", "post_params")
  end

  test "instance methods render persistence and error expressions for the configured receiver" do
    builder = Rails::Generators::ActiveModel.new("@post")

    assert_equal "@post", builder.name
    assert_equal "@post.save", builder.save
    assert_equal "@post.update(post_params)", builder.update("post_params")
    assert_equal "@post.update()", builder.update
    assert_equal "@post.errors", builder.errors
    assert_equal "@post.destroy!", builder.destroy
  end
end
