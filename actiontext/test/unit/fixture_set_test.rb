# frozen_string_literal: true

require "test_helper"

class ActionText::FixtureSetTest < ActiveSupport::TestCase
  def test_attachment_markup_uses_attachable_locator_sgid
    attachment = ActionText::FixtureSet.attachment("people", :alice)

    assert_match %r{\A<action-text-attachment sgid=".+"></action-text-attachment>\z}, attachment
    assert_equal people(:alice), ActionText::Attachable.from_node(ActionText::Fragment.wrap(attachment).find_all(ActionText::Attachment.tag_name).first)
  end

  def test_action_text_attachment
    message = messages(:hello_world)
    review = reviews(:hello_world)

    attachments = review.content.body.attachments

    assert_includes attachments.map(&:attachable), message
  end
end
