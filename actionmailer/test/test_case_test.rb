# frozen_string_literal: true

require "abstract_unit"

class TestTestMailer < ActionMailer::Base
end

class ClearTestDeliveriesMixinTest < ActiveSupport::TestCase
  include ActionMailer::TestCase::ClearTestDeliveries

  def before_setup
    ActionMailer::Base.delivery_method, @original_delivery_method = :test, ActionMailer::Base.delivery_method
    ActionMailer::Base.deliveries << "better clear me, setup"
    super
  end

  def after_teardown
    super
    assert_equal [], ActionMailer::Base.deliveries
    ActionMailer::Base.delivery_method = @original_delivery_method
  end

  def test_deliveries_are_cleared_on_setup_and_teardown
    assert_equal [], ActionMailer::Base.deliveries
    ActionMailer::Base.deliveries << "better clear me, teardown"
  end
end

class MailerDeliveriesClearingTest < ActionMailer::TestCase
  def before_setup
    ActionMailer::Base.deliveries << "better clear me, setup"
    super
  end

  def after_teardown
    super
    assert_equal [], ActionMailer::Base.deliveries
  end

  def test_deliveries_are_cleared_on_setup_and_teardown
    assert_equal [], ActionMailer::Base.deliveries
    ActionMailer::Base.deliveries << "better clear me, teardown"
  end
end

class ManuallySetNameMailerTest < ActionMailer::TestCase
  tests TestTestMailer

  def test_set_mailer_class_manual
    assert_equal TestTestMailer, self.class.mailer_class
  end
end

class ManuallySetSymbolNameMailerTest < ActionMailer::TestCase
  tests :test_test_mailer

  def test_set_mailer_class_manual_using_symbol
    assert_equal TestTestMailer, self.class.mailer_class
  end
end

class ManuallySetStringNameMailerTest < ActionMailer::TestCase
  tests "test_test_mailer"

  def test_set_mailer_class_manual_using_string
    assert_equal TestTestMailer, self.class.mailer_class
  end
end

class MailerTestCaseAccessorsTest < ActionMailer::TestCase
  tests TestTestMailer

  def test_behavior_class_attributes_can_be_reassigned
    original_decoders = self.class._decoders
    original_mailer_class = self.class._mailer_class
    custom_decoders = { Mime[:text] => ->(body) { body.upcase } }

    self.class._decoders = custom_decoders
    self.class._mailer_class = ActionMailer::Base
    self._decoders = custom_decoders
    self._mailer_class = TestTestMailer

    assert_equal custom_decoders, self.class._decoders
    assert_equal ActionMailer::Base, self.class._mailer_class
    assert_equal custom_decoders, _decoders
    assert_equal TestTestMailer, _mailer_class
  ensure
    self.class._decoders = original_decoders
    self.class._mailer_class = original_mailer_class
  end

  def test_invalid_mailer_specification_raises_non_inferrable_error
    error = assert_raises(ActionMailer::NonInferrableMailerError) do
      self.class.tests Object.new
    end

    assert_match "Unable to determine the mailer to test", error.message
  ensure
    self.class.tests TestTestMailer
  end
end
