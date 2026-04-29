# frozen_string_literal: true

require_relative "../test_helper"

module ActionMailbox
  class TestHelperTest < ActiveSupport::TestCase
    test "creates inbound email from fixture" do
      inbound_email = create_inbound_email_from_fixture "welcome.eml", status: :pending

      assert_predicate inbound_email, :pending?
      assert_equal "Discussion: Let's debate these attachments", inbound_email.mail.subject
    end

    test "creates inbound email from raw source" do
      inbound_email = create_inbound_email_from_source file_fixture("welcome.eml").read, status: :failed

      assert_predicate inbound_email, :failed?
      assert_equal "Discussion: Let's debate these attachments", inbound_email.mail.subject
    end

    test "creates inbound email from mail options with bcc header" do
      inbound_email = create_inbound_email_from_mail from: "sally@example.com", bcc: "hidden@example.com", subject: "Secret"

      assert_equal [ "hidden@example.com" ], inbound_email.mail.bcc
      assert_match "Bcc: hidden@example.com", inbound_email.source
    end

    test "receives inbound email from fixture" do
      assert_receive_routes do
        receive_inbound_email_from_fixture "welcome.eml"
      end
    end

    test "receives inbound email from mail" do
      assert_receive_routes do
        receive_inbound_email_from_mail from: "sally@example.com", to: "test@example.com", subject: "Hello"
      end
    end

    test "receives inbound email from source" do
      assert_receive_routes do
        receive_inbound_email_from_source file_fixture("welcome.eml").read
      end
    end

    test "multi-part mail can be built in tests using a block" do
      inbound_email = create_inbound_email_from_mail do
        to "test@example.com"
        from "hello@example.com"

        text_part do
          body "Hello, world"
        end

        html_part do
          body "<h1>Hello, world</h1>"
        end
      end

      mail = inbound_email.mail

      expected_mail_text_part = <<~TEXT.chomp
        Content-Type: text/plain;\r
         charset=UTF-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        Hello, world
      TEXT

      expected_mail_html_part = <<~HTML.chomp
        Content-Type: text/html;\r
         charset=UTF-8\r
        Content-Transfer-Encoding: 7bit\r
        \r
        <h1>Hello, world</h1>
      HTML

      assert_equal 2, mail.parts.count
      assert_equal expected_mail_text_part, mail.text_part.to_s
      assert_equal expected_mail_html_part, mail.html_part.to_s
    end
    private
      def assert_receive_routes
        original_router = ApplicationMailbox.router
        routed = []
        fake_router = Object.new
        fake_router.define_singleton_method(:route) { |inbound_email| routed << inbound_email }

        ApplicationMailbox.router = fake_router
        inbound_email = yield

        assert_equal [ inbound_email ], routed
      ensure
        ApplicationMailbox.router = original_router
      end
  end
end
