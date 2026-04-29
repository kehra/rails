# frozen_string_literal: true

require "cases/helper"

class ActiveModelVersionTest < ActiveModel::TestCase
  test "gem_version returns the configured version" do
    assert_equal Gem::Version.new(ActiveModel::VERSION::STRING), ActiveModel.gem_version
  end

  test "version delegates to gem_version" do
    assert_equal ActiveModel.gem_version, ActiveModel.version
  end

  test "deprecator is memoized" do
    assert_same ActiveModel.deprecator, ActiveModel.deprecator
    assert_instance_of ActiveSupport::Deprecation, ActiveModel.deprecator
  end
end
