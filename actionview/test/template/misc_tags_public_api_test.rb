# frozen_string_literal: true

require "abstract_unit"
require "action_view/helpers/tags/label"

class MiscTagsPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::FormHelper

  class Model
    attr_accessor :quantity

    def title
      "Hello"
    end
  end

  test "label builder stringifies translated content" do
    builder = ActionView::Helpers::Tags::Label::LabelBuilder.new(self, "post", "title", Model.new, nil)

    assert_equal "Title", builder.to_s
  end

  test "number field renders without range options" do
    model = Model.new
    model.quantity = 2

    output = number_field("post", "quantity", object: model)

    assert_dom_equal '<input type="number" value="2" name="post[quantity]" id="post_quantity" />', output
  end

  test "search field derives autosave from request host and preserves explicit incremental" do
    tag = ActionView::Helpers::Tags::SearchField.new("post", "title", self, autosave: true)
    request = Struct.new(:host).new("www.example.com")
    tag.define_singleton_method(:request) { request }

    output = tag.render
    assert_includes output, 'autosave="com.example.www"'
    assert_includes output, 'results="10"'

    output = search_field("post", "title", autosave: "drafts", onsearch: "find()", incremental: false)
    assert_includes output, 'autosave="drafts"'
    assert_includes output, 'onsearch="find()"'
    assert_includes output, 'incremental="false"'
  end

  test "textarea ignores non string size and time field handles nil without seconds" do
    output = text_area("post", "title", size: 10)
    assert_not_includes output, "cols="
    assert_not_includes output, "rows="

    output = time_field("post", "started_at", include_seconds: false)
    assert_includes output, 'type="time"'
    assert_not_includes output, 'value='
  end
end
