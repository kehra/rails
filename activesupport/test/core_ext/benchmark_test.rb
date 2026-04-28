# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/core_ext/benchmark"

class CoreExtBenchmarkTest < ActiveSupport::TestCase
  test "benchmark core extension entrypoint loads" do
    assert_nothing_raised { require "active_support/core_ext/benchmark" }
  end
end
