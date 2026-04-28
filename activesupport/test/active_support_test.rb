# frozen_string_literal: true

require_relative "abstract_unit"

class ActiveSupportTest < ActiveSupport::TestCase
  test "gem_version returns the active support version" do
    assert_equal Gem::Version.new(ActiveSupport::VERSION::STRING), ActiveSupport.gem_version
  end

  test "version returns the active support gem version" do
    assert_equal ActiveSupport.gem_version, ActiveSupport.version
  end

  test "cache_format_version returns the cache format version" do
    original_format_version = ActiveSupport::Cache.format_version

    ActiveSupport::Cache.format_version = 7.0
    assert_equal 7.0, ActiveSupport.cache_format_version

    ActiveSupport::Cache.format_version = 7.1
    assert_equal 7.1, ActiveSupport.cache_format_version
  ensure
    ActiveSupport::Cache.format_version = original_format_version
  end

  test "cache_format_version= sets the cache format version" do
    original_format_version = ActiveSupport::Cache.format_version

    ActiveSupport.cache_format_version = 7.0
    assert_equal 7.0, ActiveSupport::Cache.format_version

    ActiveSupport.cache_format_version = 7.1
    assert_equal 7.1, ActiveSupport::Cache.format_version
  ensure
    ActiveSupport::Cache.format_version = original_format_version
  end

  test "eager_load! eager loads Active Support and number helper constants" do
    ActiveSupport.eager_load!

    assert ActiveSupport.const_defined?(:BacktraceCleaner, false)
    assert ActiveSupport.const_defined?(:NumberHelper, false)
    assert ActiveSupport::NumberHelper.const_defined?(:NumberConverter, false)
    assert_nil ActiveSupport.instance_variable_get(:@_eagerloaded_constants)
    assert_nil ActiveSupport::NumberHelper.instance_variable_get(:@_eagerloaded_constants)
  end

  test "to_time_preserves_timezone returns the configured value with a deprecation warning" do
    original_value = ActiveSupport.instance_variable_get(:@to_time_preserves_timezone)

    ActiveSupport.instance_variable_set(:@to_time_preserves_timezone, true)
    assert_deprecated(/to_time_preserves_timezone/, ActiveSupport.deprecator) do
      assert_equal true, ActiveSupport.to_time_preserves_timezone
    end

    ActiveSupport.instance_variable_set(:@to_time_preserves_timezone, false)
    assert_deprecated(/to_time_preserves_timezone/, ActiveSupport.deprecator) do
      assert_equal false, ActiveSupport.to_time_preserves_timezone
    end
  ensure
    ActiveSupport.instance_variable_set(:@to_time_preserves_timezone, original_value)
  end

  test "to_time_preserves_timezone= sets the configured value with a deprecation warning" do
    original_value = ActiveSupport.instance_variable_get(:@to_time_preserves_timezone)

    assert_deprecated(/to_time_preserves_timezone/, ActiveSupport.deprecator) do
      ActiveSupport.to_time_preserves_timezone = true
    end
    assert_equal true, ActiveSupport.instance_variable_get(:@to_time_preserves_timezone)

    assert_deprecated(/to_time_preserves_timezone/, ActiveSupport.deprecator) do
      ActiveSupport.to_time_preserves_timezone = false
    end
    assert_equal false, ActiveSupport.instance_variable_get(:@to_time_preserves_timezone)
  ensure
    ActiveSupport.instance_variable_set(:@to_time_preserves_timezone, original_value)
  end

  test "active_support/all loads Active Support time and core extensions" do
    require "active_support/all"

    assert_equal 2.days, 48.hours
    assert_equal Date.new(2026, 4, 29), Date.new(2026, 4, 28).advance(days: 1)
    assert_predicate "", :blank?
  end

  test "active_support/rails loads Rails component dependencies" do
    require "active_support/rails"

    assert_predicate "", :blank?
    assert_respond_to Class.new, :class_attribute
    assert_respond_to Module.new, :delegate
    assert_kind_of ActiveSupport::Deprecation, ActiveSupport.deprecator
  end
end
