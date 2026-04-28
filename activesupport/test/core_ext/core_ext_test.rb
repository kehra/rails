# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/core_ext"

class CoreExtTest < ActiveSupport::TestCase
  test "loads core extension entrypoint" do
    assert "hello".blank? == false
    assert_equal 1.day, 24.hours
    assert_equal({ a: 1 }, { "a" => 1 }.symbolize_keys)
  end
end
