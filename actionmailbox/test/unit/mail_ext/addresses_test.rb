# frozen_string_literal: true

require_relative "../../test_helper"

module MailExt
  class AddressesTest < ActiveSupport::TestCase
    setup do
      @mail = Mail.new \
        from: "sally@example.com",
        reply_to: "sarah@example.com",
        to: "david@basecamp.com",
        cc: "jason@basecamp.com",
        bcc: "andrea@basecamp.com",
        x_original_to: "ryan@basecamp.com",
        x_forwarded_to: "jane@example.com"
    end

    test "from address uses address object" do
      assert_equal "example.com", @mail.from_address.domain
    end

    test "reply to address uses address object" do
      assert_equal "example.com", @mail.reply_to_address.domain
    end

    test "recipients include everyone from to, cc, bcc, x-original-to, and x-forwarded-to" do
      assert_equal %w[ david@basecamp.com jason@basecamp.com andrea@basecamp.com ryan@basecamp.com jane@example.com ], @mail.recipients
    end

    test "recipients addresses use address objects" do
      assert_equal "basecamp.com", @mail.recipients_addresses.first.domain
    end

    test "to addresses use address objects" do
      assert_equal "basecamp.com", @mail.to_addresses.first.domain
    end

    test "cc addresses use address objects" do
      assert_equal "basecamp.com", @mail.cc_addresses.first.domain
    end

    test "bcc addresses use address objects" do
      assert_equal "basecamp.com", @mail.bcc_addresses.first.domain
    end

    test "x_original_to addresses use address objects" do
      assert_equal "basecamp.com", @mail.x_original_to_addresses.first.domain
    end

    test "x_forwarded_to addresses use address objects" do
      assert_equal "example.com", @mail.x_forwarded_to_addresses.first.domain
    end

    test "standard address helpers use parsed field elements" do
      assert_same @mail.header[:from].element.addresses.first, @mail.from_address
      assert_same @mail.header[:reply_to].element.addresses.first, @mail.reply_to_address
      assert_equal @mail.header[:to].element.addresses, @mail.to_addresses
      assert_equal @mail.header[:cc].element.addresses, @mail.cc_addresses
      assert_equal @mail.header[:bcc].element.addresses, @mail.bcc_addresses
    end

    test "missing address headers return empty address collections" do
      mail = Mail.new

      assert_nil mail.from_address
      assert_nil mail.reply_to_address
      assert_empty mail.to_addresses
      assert_empty mail.cc_addresses
      assert_empty mail.bcc_addresses
      assert_empty mail.recipients_addresses
    end
  end
end
