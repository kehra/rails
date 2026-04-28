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
end
