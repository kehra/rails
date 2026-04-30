# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/core_ext/thread/backtrace/location"

class ThreadBacktraceLocationTest < ActiveSupport::TestCase
  def test_spot_delegates_to_error_highlight
    location = caller_locations(1, 1).first
    error = NoMethodError.new("missing")

    ErrorHighlight.stub(:spot, ->(exception, backtrace_location:) { [exception, backtrace_location] }) do
      assert_equal [error, location], location.spot(error)
    end
  end
end
