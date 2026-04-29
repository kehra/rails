# frozen_string_literal: true

require "abstract_unit"
require "action_pack"

class ActionPackVersionTest < ActiveSupport::TestCase
  test "gem version returns the version string as a Gem::Version" do
    assert_equal Gem::Version.new(ActionPack::VERSION::STRING), ActionPack.gem_version
  end

  test "version delegates to gem version" do
    assert_equal ActionPack.gem_version, ActionPack.version
  end
end
