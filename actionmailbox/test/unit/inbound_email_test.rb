# frozen_string_literal: true

require_relative "../test_helper"
require "minitest/mock"

module ActionMailbox
  class InboundEmailTest < ActiveSupport::TestCase
    test "mail provides the parsed source" do
      assert_equal "Discussion: Let's debate these attachments", create_inbound_email_from_fixture("welcome.eml").mail.subject
    end

    test "source returns the contents of the raw email" do
      assert_equal file_fixture("welcome.eml").read, create_inbound_email_from_fixture("welcome.eml").source
    end

    test "status enum predicates, transitions, scopes, and processed state" do
      statuses = %w[ pending processing delivered failed bounced ]
      inbound_emails = statuses.index_with do |status|
        create_inbound_email_from_mail(status: status, from: "sender-#{status}@example.com", to: "receiver@example.com", subject: "#{status} message")
      end

      assert inbound_emails["pending"].pending?
      assert inbound_emails["processing"].processing?
      assert inbound_emails["delivered"].delivered?
      assert inbound_emails["failed"].failed?
      assert inbound_emails["bounced"].bounced?

      assert_not inbound_emails["pending"].processed?
      assert_not inbound_emails["processing"].processed?
      assert inbound_emails["delivered"].processed?
      assert inbound_emails["failed"].processed?
      assert inbound_emails["bounced"].processed?

      assert_includes ActionMailbox::InboundEmail.pending, inbound_emails["pending"]
      assert_includes ActionMailbox::InboundEmail.processing, inbound_emails["processing"]
      assert_includes ActionMailbox::InboundEmail.delivered, inbound_emails["delivered"]
      assert_includes ActionMailbox::InboundEmail.failed, inbound_emails["failed"]
      assert_includes ActionMailbox::InboundEmail.bounced, inbound_emails["bounced"]

      inbound_email = inbound_emails["pending"]
      inbound_email.processing!
      assert inbound_email.processing?
      inbound_email.delivered!
      assert inbound_email.delivered?
      inbound_email.failed!
      assert inbound_email.failed?
      inbound_email.bounced!
      assert inbound_email.bounced?
      inbound_email.pending!
      assert inbound_email.pending?
    end

    test "raw_email is stored as an rfc822 attachment" do
      inbound_email = create_inbound_email_from_fixture("welcome.eml")

      assert inbound_email.raw_email.attached?
      assert_equal "message.eml", inbound_email.raw_email.filename.to_s
      assert_equal "message/rfc822", inbound_email.raw_email.content_type
      assert_equal file_fixture("welcome.eml").read, inbound_email.raw_email.download
    end

    test "email with message id is processed only once when received multiple times" do
      mail = Mail.from_source(file_fixture("welcome.eml").read)
      assert mail.message_id

      inbound_email_1 = create_inbound_email_from_source(mail.to_s)
      assert inbound_email_1

      inbound_email_2 = create_inbound_email_from_source(mail.to_s)
      assert_nil inbound_email_2
    end

    test "email with missing message id is processed only once when received multiple times" do
      mail = Mail.from_source("Date: Fri, 28 Sep 2018 11:08:55 -0700\r\nTo: a@example.com\r\nMime-Version: 1.0\r\nContent-Type: text/plain\r\nContent-Transfer-Encoding: 7bit\r\n\r\nHello!")
      assert_nil mail.message_id

      inbound_email_1 = create_inbound_email_from_source(mail.to_s)
      assert inbound_email_1

      inbound_email_2 = create_inbound_email_from_source(mail.to_s)
      assert_nil inbound_email_2
    end

    test "error on upload doesn't leave behind a pending inbound email" do
      ActiveStorage::Blob.service.stub(:upload, -> { raise "Boom!" }) do
        assert_no_difference -> { ActionMailbox::InboundEmail.count } do
          assert_raises do
            create_inbound_email_from_fixture "welcome.eml"
          end
        end
      end
    end

    test "email gets saved to the configured storage service" do
      ActionMailbox.storage_service = :test_email

      assert_equal(:test_email, ActionMailbox.storage_service)

      email = create_inbound_email_from_fixture("welcome.eml")

      storage_service = ActiveStorage::Blob.services.fetch(ActionMailbox.storage_service)
      raw = email.raw_email_blob

      # Not present in the main storage
      assert_not(ActiveStorage::Blob.service.exist?(raw.key))
      # Present in the email storage
      assert(storage_service.exist?(raw.key))
    ensure
      ActionMailbox.storage_service = nil
    end

    test "email gets saved to the default storage service, even if it gets changed" do
      default_service = ActiveStorage::Blob.service
      ActiveStorage::Blob.service = ActiveStorage::Blob.services.fetch(:test_email)

      # Doesn't change ActionMailbox.storage_service
      assert_nil(ActionMailbox.storage_service)

      email = create_inbound_email_from_fixture("welcome.eml")
      raw = email.raw_email_blob

      # Not present in the (previously) default storage
      assert_not(default_service.exist?(raw.key))
      # Present in the current default storage (email)
      assert(ActiveStorage::Blob.service.exist?(raw.key))
    ensure
      ActiveStorage::Blob.service = default_service
    end
  end
end
