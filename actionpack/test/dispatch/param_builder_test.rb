# frozen_string_literal: true

require "abstract_unit"

class ParamBuilderTest < ActiveSupport::TestCase
  # Much of the behavioral details are covered by long-standing
  # integration tests in test/request/query_string_parsing_test.rb
  #
  # This test doesn't need to duplicate all of that: it just
  # offers a simple baseline of unit tests.

  test "simple query string" do
    result = ActionDispatch::ParamBuilder.from_query_string("foo=bar&baz=quux")
    assert_equal({ "foo" => "bar", "baz" => "quux" }, result)
    assert_instance_of ActiveSupport::HashWithIndifferentAccess, result
  end

  test "nested parameters" do
    result = ActionDispatch::ParamBuilder.from_query_string("foo[bar]=baz")
    assert_equal({ "foo" => { "bar" => "baz" } }, result)
    assert_instance_of ActiveSupport::HashWithIndifferentAccess, result[:foo]
  end

  test "retaining leading bracket" do
    result = ActionDispatch::ParamBuilder.from_query_string("[foo]=bar")
    assert_equal({ "[foo]" => "bar" }, result)

    result = ActionDispatch::ParamBuilder.from_query_string("[foo][bar]=baz")
    assert_equal({ "[foo]" => { "bar" => "baz" } }, result)
  end

  test "from pairs converts upload hashes and wraps parameter errors" do
    tempfile = Tempfile.new("upload")
    params = ActionDispatch::ParamBuilder.from_pairs([
      ["file", { filename: "avatar.png", type: "image/png", tempfile: tempfile, head: "" }],
    ])

    assert_instance_of ActionDispatch::Http::UploadedFile, params[:file]
    assert_equal "avatar.png", params[:file].original_filename

    invalid_key = +"bad\xFF"
    invalid_key.force_encoding(Encoding::UTF_8)

    assert_raises(ActionDispatch::InvalidParameterError) do
      ActionDispatch::ParamBuilder.from_pairs([[invalid_key, "value"]])
    end
  ensure
    tempfile&.close!
  end

  test "from hash normalizes nested parameters and uploaded files" do
    tempfile = Tempfile.new("upload")
    params = ActionDispatch::ParamBuilder.from_hash({
      "file" => { filename: "avatar.png", type: "image/png", tempfile: tempfile, head: "" },
      "tags" => [nil, "ruby"]
    })

    assert_instance_of ActiveSupport::HashWithIndifferentAccess, params
    assert_instance_of ActionDispatch::Http::UploadedFile, params[:file]
    assert_equal ["ruby"], params[:tags]
  ensure
    tempfile&.close!
  end

  test "default builder accessors and depth limit" do
    original_default = ActionDispatch::ParamBuilder.default
    builder = ActionDispatch::ParamBuilder.make_default(1)

    assert_equal 1, builder.param_depth_limit
    assert_equal original_default, builder.default

    builder.default = builder
    assert_same builder, ActionDispatch::ParamBuilder.default
    assert_same builder, builder.default

    assert_raises(ActionDispatch::ParamsTooDeepError) do
      ActionDispatch::ParamBuilder.from_query_string("person[name]=David")
    end
  ensure
    ActionDispatch::ParamBuilder.default = original_default
  end

  test "deprecated ignore leading brackets accessors store class state" do
    ActionDispatch.deprecator.silence do
      original = ActionDispatch::ParamBuilder.ignore_leading_brackets
      ActionDispatch::ParamBuilder.ignore_leading_brackets = true
      assert_equal true, ActionDispatch::ParamBuilder.ignore_leading_brackets
    ensure
      ActionDispatch::ParamBuilder.ignore_leading_brackets = original
    end
  end
end
