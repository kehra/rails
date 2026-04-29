# frozen_string_literal: true

require_relative "../../test_helper"

module MailExt
  class FromSourceTest < ActiveSupport::TestCase
    test "from_source normalizes line endings and parses mail" do
      mail = Mail.from_source "From: sally@example.com\nTo: david@example.com\nSubject: Hello\n\nHi"

      assert_equal [ "sally@example.com" ], mail.from
      assert_equal [ "david@example.com" ], mail.to
      assert_equal "Hello", mail.subject
      assert_equal "Hi", mail.body.decoded
    end
  end
end
