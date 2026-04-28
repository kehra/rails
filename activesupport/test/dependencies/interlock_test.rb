# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/dependencies"

class DependenciesInterlockTest < ActiveSupport::TestCase
  def setup
    @interlock = ActiveSupport::Dependencies::Interlock.new
  end

  test "loading is deprecated and yields only when block given" do
    assert_deprecated(/Interlock#loading is deprecated/, ActiveSupport.deprecator) do
      assert_equal :loading, @interlock.loading { :loading }
    end

    assert_deprecated(/Interlock#loading is deprecated/, ActiveSupport.deprecator) do
      assert_nil @interlock.loading
    end
  end

  test "unloading yields block value" do
    assert_equal :unloading, @interlock.unloading { :unloading }
  end

  test "manual unloading lifecycle updates raw state" do
    @interlock.start_unloading

    state = @interlock.raw_state { |raw_state| raw_state }
    assert state[Thread.current][:exclusive]
  ensure
    @interlock.done_unloading if state
  end

  test "manual running lifecycle updates raw state" do
    @interlock.start_running

    state = @interlock.raw_state { |raw_state| raw_state }
    assert_equal 1, state[Thread.current][:sharing]
  ensure
    @interlock.done_running if state
  end

  test "running yields block value" do
    assert_equal :running, @interlock.running { :running }
  end

  test "permit concurrent loads yields only when block given" do
    assert_equal :permitted, @interlock.permit_concurrent_loads { :permitted }
    assert_nil @interlock.permit_concurrent_loads
  end
end
