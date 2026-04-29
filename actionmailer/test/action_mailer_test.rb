# frozen_string_literal: true

require "abstract_unit"

class ActionMailerTest < ActiveSupport::TestCase
  test "gem version returns the current Action Mailer version" do
    assert_equal Gem::Version.new(ActionMailer::VERSION::STRING), ActionMailer.gem_version
  end

  test "version delegates to gem version" do
    assert_equal ActionMailer.gem_version, ActionMailer.version
  end
end
