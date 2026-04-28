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
end
