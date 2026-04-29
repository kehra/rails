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
end
