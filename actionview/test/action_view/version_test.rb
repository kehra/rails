# frozen_string_literal: true

require "abstract_unit"
require "action_view"

class ActionViewVersionTest < ActiveSupport::TestCase
  test "gem version returns the version string as a Gem::Version" do
    assert_equal Gem::Version.new(ActionView::VERSION::STRING), ActionView.gem_version
  end

  test "version delegates to gem version" do
    assert_equal ActionView.gem_version, ActionView.version
  end
end
