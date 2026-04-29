# frozen_string_literal: true

require_relative "../../test_helper"

class ApplicationMailbox < ActionMailbox::Base
  routing "replies@example.com" => :replies
end

class RepliesMailbox < ActionMailbox::Base
  def process
    $processed = mail.subject
  end
end

class ActionMailbox::Base::RoutingTest < ActiveSupport::TestCase
  setup do
    $processed = false
  end

  test "string routing" do
    ApplicationMailbox.route create_inbound_email_from_fixture("welcome.eml")
    assert_equal "Discussion: Let's debate these attachments", $processed
  end

  test "delayed routing" do
    perform_enqueued_jobs only: ActionMailbox::RoutingJob do
      create_inbound_email_from_fixture "welcome.eml", status: :pending
      assert_equal "Discussion: Let's debate these attachments", $processed
    end
  end

  test "route_later enqueues routing job" do
    inbound_email = create_inbound_email_from_fixture "welcome.eml", status: :processing

    assert_enqueued_with job: ActionMailbox::RoutingJob, args: [ inbound_email ] do
      inbound_email.route_later
    end
  end

  test "route delegates to ApplicationMailbox" do
    inbound_email = create_inbound_email_from_fixture "welcome.eml", status: :processing

    inbound_email.route

    assert_equal "Discussion: Let's debate these attachments", $processed
  end

  test "mailbox_for" do
    inbound_email = create_inbound_email_from_fixture "welcome.eml", status: :pending
    assert_equal RepliesMailbox, ApplicationMailbox.mailbox_for(inbound_email)
  end
end
