# frozen_string_literal: true

require_relative "abstract_unit"

class ActiveSupportTest < ActiveSupport::TestCase
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
end
