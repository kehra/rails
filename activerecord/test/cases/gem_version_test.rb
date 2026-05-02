# frozen_string_literal: true

require "cases/helper"
require "active_record/gem_version"

class GemVersionTest < ActiveRecord::TestCase
  def test_gem_version_returns_version_string_as_gem_version
    version = ActiveRecord.gem_version

    assert_instance_of Gem::Version, version
    assert_equal ActiveRecord::VERSION::STRING, version.to_s
  end

  def test_version_string_is_built_from_version_parts
    assert_equal [
      ActiveRecord::VERSION::MAJOR,
      ActiveRecord::VERSION::MINOR,
      ActiveRecord::VERSION::TINY,
      ActiveRecord::VERSION::PRE,
    ].compact.join("."), ActiveRecord::VERSION::STRING
  end
end
