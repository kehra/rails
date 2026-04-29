# frozen_string_literal: true

require "test_helper"

class ActionMailboxTest < ActiveSupport::TestCase
  test "module accessors read and write configuration" do
    old_values = {
      incinerate: ActionMailbox.incinerate,
      incinerate_after: ActionMailbox.incinerate_after,
      ingress: ActionMailbox.ingress,
      logger: ActionMailbox.logger,
      queues: ActionMailbox.queues,
      storage_service: ActionMailbox.storage_service,
    }

    logger = Logger.new(nil)
    ActionMailbox.incinerate = false
    ActionMailbox.incinerate_after = 2.days
    ActionMailbox.ingress = :relay
    ActionMailbox.logger = logger
    ActionMailbox.queues = { routing: :custom_routing }
    ActionMailbox.storage_service = :test_email

    assert_equal false, ActionMailbox.incinerate
    assert_equal 2.days, ActionMailbox.incinerate_after
    assert_equal :relay, ActionMailbox.ingress
    assert_same logger, ActionMailbox.logger
    assert_equal({ routing: :custom_routing }, ActionMailbox.queues)
    assert_equal :test_email, ActionMailbox.storage_service
  ensure
    old_values&.each { |name, value| ActionMailbox.public_send("#{name}=", value) }
  end

  test "module accessors are available as instance methods" do
    object = Object.new.extend(ActionMailbox)

    object.incinerate = false
    object.incinerate_after = 1.day
    object.ingress = :mailgun
    object.logger = Logger.new(nil)
    object.queues = { incineration: :low_priority }
    object.storage_service = :test_email

    assert_equal false, object.incinerate
    assert_equal 1.day, object.incinerate_after
    assert_equal :mailgun, object.ingress
    assert_instance_of Logger, object.logger
    assert_equal({ incineration: :low_priority }, object.queues)
    assert_equal :test_email, object.storage_service
  ensure
    ActionMailbox.incinerate = true
    ActionMailbox.incinerate_after = 30.days
    ActionMailbox.ingress = nil
    ActionMailbox.logger = nil
    ActionMailbox.queues = {}
    ActionMailbox.storage_service = nil
  end

  test "version helpers return current gem version" do
    assert_equal Gem::Version.new(ActionMailbox::VERSION::STRING), ActionMailbox.gem_version
    assert_equal ActionMailbox.gem_version, ActionMailbox.version
  end
end
