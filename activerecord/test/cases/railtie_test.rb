# frozen_string_literal: true

require "cases/helper"

RAILS_DEFINED_BEFORE_ACTIVE_RECORD_RAILTIE_TEST = Object.const_defined?(:Rails)
require "active_record/railtie"

class ActiveRecordRailtieTest < ActiveRecord::TestCase
  teardown do
    Object.send(:remove_const, :Rails) if !RAILS_DEFINED_BEFORE_ACTIVE_RECORD_RAILTIE_TEST && Object.const_defined?(:Rails)
  end

  def test_railtie_default_configuration
    config = ActiveRecord::Railtie.config.active_record

    assert_equal true, config.use_schema_cache_dump
    assert_equal true, config.check_schema_cache_dump_version
    assert_equal true, config.maintain_test_schema
    assert_equal false, config.has_many_inversing
    assert_equal false, config.query_log_tags_enabled
    assert_equal [:application], config.query_log_tags
    assert_equal :legacy, config.query_log_tags_format
    assert_equal false, config.cache_query_log_tags
    assert_equal false, config.query_log_tags_prepend_comment
    assert_equal false, config.raise_on_assign_to_attr_readonly
    assert_equal true, config.belongs_to_required_validates_foreign_key
    assert_equal :create, config.generate_secure_token_on
    assert_equal :generate_and_verify, config.use_legacy_signed_id_verifier
    assert_equal({ mode: :warn, backtrace: false }, config.deprecated_associations_options)
    assert_instance_of ActiveSupport::OrderedOptions, config.encryption
    assert_instance_of ActiveSupport::InheritableOptions, config.queues
  end

  def test_railtie_rescue_responses
    responses = ActiveRecord::Railtie.config.action_dispatch.rescue_responses

    assert_equal :not_found, responses["ActiveRecord::RecordNotFound"]
    assert_equal :conflict, responses["ActiveRecord::StaleObjectError"]
    assert_equal ActionDispatch::Constants::UNPROCESSABLE_CONTENT, responses["ActiveRecord::RecordInvalid"]
    assert_equal ActionDispatch::Constants::UNPROCESSABLE_CONTENT, responses["ActiveRecord::RecordNotSaved"]
  end

  def test_railtie_registers_active_record_initializers
    initializer_names = ActiveRecord::Railtie.initializers.map(&:name)

    assert_includes initializer_names, "active_record.deprecator"
    assert_includes initializer_names, "active_record.initialize_timezone"
    assert_includes initializer_names, "active_record.logger"
    assert_includes initializer_names, "active_record.initialize_database"
    assert_includes initializer_names, "active_record.log_runtime"
    assert_includes initializer_names, "active_record.query_log_tags_config"
    assert_includes initializer_names, "active_record.message_pack"
  end
end
