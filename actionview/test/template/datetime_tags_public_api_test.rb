# frozen_string_literal: true

require "abstract_unit"
require "action_view/helpers/tags/datetime_field"

class DatetimeTagsPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::FormHelper

  class DateModel
    attr_accessor :written_on, :started_at, :attachment
  end

  test "base datetime field render requires subclass format hook" do
    model = DateModel.new
    model.started_at = Time.utc(2024, 1, 2, 3, 4, 5)

    tag = ActionView::Helpers::Tags::DatetimeField.new("post", "started_at", self, object: model)

    assert_raises(NotImplementedError) { tag.render }
  end
end
