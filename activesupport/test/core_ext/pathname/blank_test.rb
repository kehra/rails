# frozen_string_literal: true

require_relative "../../abstract_unit"
require "active_support/core_ext/pathname"

class PathnameBlankTest < ActiveSupport::TestCase
  def test_blank
    assert_predicate Pathname.new(""), :blank?
    assert_not_predicate Pathname.new("test"), :blank?
    assert_not_predicate Pathname.new(" "), :blank?
  end

  def test_present
    assert_not_predicate Pathname.new(""), :present?
    assert_predicate Pathname.new("test"), :present?
  end
end
