# frozen_string_literal: true

require "abstract_unit"
require "action_view/render_parser"

class ActionViewRenderParserTest < ActiveSupport::TestCase
  def render_calls(code, name: "posts/show")
    ActionView::RenderParser.new(name, code).render_calls
  end

  test "finds partials and templates from render calls" do
    assert_equal ["posts/_post"], render_calls(%q(render partial: "posts/post"))
    assert_equal ["posts/show"], render_calls(%q(render template: "posts/show"))
    assert_equal ["posts/show"], render_calls(%q(render_to_string template: "posts/show"))
  end

  test "normalizes relative string partials against the current template directory" do
    assert_equal ["admin/posts/_form"], render_calls(%q(render "form"), name: "admin/posts/edit")
    assert_equal ["admin/posts/_form"], render_calls(%q(render(("form"))), name: "admin/posts/edit")
  end

  test "adds layout and spacer template dependencies" do
    assert_equal ["posts/_spacer", "posts/_post", "layouts/_card"], render_calls(%q(
      render partial: "posts/post", layout: "layouts/card", collection: posts, spacer_template: "posts/spacer"
    ))
  end

  test "infers object templates from variable and call nodes" do
    assert_equal ["messages/_message"], render_calls(%q(message = nil; render message))
    assert_equal ["messages/_message"], render_calls(%q(render @messages))
    assert_equal ["messages/_message"], render_calls(%q(render $messages))
    assert_equal ["messages/_message"], render_calls(%q(render @@messages))
    assert_equal ["comments/_comment"], render_calls(%q(render post.comments))
  end

  test "uses wildcard for embedded statements in interpolated strings" do
    assert_equal ["posts/*/_summary"], render_calls(%q(render "posts/#{status}/summary"))
  end

  test "ignores unsupported and ambiguous render calls" do
    assert_equal [], render_calls(%q(render))
    assert_equal [], render_calls(%q(render "posts/post", {}, :extra))
    assert_equal [], render_calls(%q(render(**options)))
    assert_equal [], render_calls(%q(render locals: { title: "Title" }))
    assert_equal [], render_calls(%q(render partial: "posts/post", unknown: true))
    assert_equal [], render_calls(%q(render partial: "posts/post", object: post, collection: posts))
    assert_equal [], render_calls(%q(render template: "posts/show", object: post))
    assert_equal [], render_calls(%q(render partial: [:posts, :post]))
  end
end
