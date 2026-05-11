# frozen_string_literal: true

require_relative "../../test_helper"

class SuccessfulMailbox < ActionMailbox::Base
  def process
    $processed = mail.subject
  end
end

class UnsuccessfulMailbox < ActionMailbox::Base
  rescue_from(RuntimeError) { $processed = :failure }

  def process
    raise "No way!"
  end
end

class BouncingMailbox < ActionMailbox::Base
  def process
    $processed = :bounced
    bounced!
  end
end


class ActionMailbox::Base::StateTest < ActiveSupport::TestCase
  setup do
    $processed = false
    @inbound_email = create_inbound_email_from_mail \
      to: "replies@example.com", subject: "I was processed"
  end

  test "successful mailbox processing leaves inbound email in delivered state" do
    SuccessfulMailbox.receive @inbound_email
    assert_predicate @inbound_email, :delivered?
    assert_equal "I was processed", $processed
  end

  test "mailbox exposes inbound email, mail, logger, and delegated state changes" do
    mailbox = ActionMailbox::Base.new(@inbound_email)

    assert_same @inbound_email, mailbox.inbound_email
    assert_equal "I was processed", mailbox.mail.subject
    if ActionMailbox.logger
      assert_same ActionMailbox.logger, mailbox.logger
    else
      assert_nil mailbox.logger
    end
    assert_nil mailbox.process

    mailbox.delivered!
    assert_predicate @inbound_email, :delivered?
    mailbox.bounced!
    assert_predicate @inbound_email, :bounced?
  end

  test "unsuccessful mailbox processing leaves inbound email in failed state" do
    UnsuccessfulMailbox.receive @inbound_email
    assert_predicate @inbound_email, :failed?
    assert_equal :failure, $processed
  end

  test "bounced inbound emails are not delivered" do
    BouncingMailbox.receive @inbound_email
    assert_predicate @inbound_email, :bounced?
    assert_equal :bounced, $processed
  end
end
