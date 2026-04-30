# frozen_string_literal: true

ORIGINAL_PROCESS_CLOCK_GETTIME = Process.method(:clock_gettime)
ORIGINAL_GC_RESPOND_TO = GC.method(:respond_to?)
ORIGINAL_GC_STAT = GC.method(:stat)
INSTRUMENTER_PATH = File.expand_path("../../lib/active_support/notifications/instrumenter.rb", __dir__)

verbose = $VERBOSE
$VERBOSE = nil
Process.define_singleton_method(:clock_gettime) do |clock_id, *args|
  raise "unsupported clock" if clock_id == Process::CLOCK_THREAD_CPUTIME_ID
  ORIGINAL_PROCESS_CLOCK_GETTIME.call(clock_id, *args)
end
GC.define_singleton_method(:respond_to?) do |name, include_private = false|
  name == :total_time ? false : ORIGINAL_GC_RESPOND_TO.call(name, include_private)
end
GC.define_singleton_method(:stat) do |key = nil|
  key ? 0 : {}
end

require_relative "../abstract_unit"
load INSTRUMENTER_PATH
$VERBOSE = verbose

class NotificationsInstrumenterFallbackTest < ActiveSupport::TestCase
  def test_event_uses_fallback_runtime_counters
    event = ActiveSupport::Notifications::Event.new("fallback", Time.now, Time.now, "id", {})
    event.start!
    event.finish!

    assert_equal 0.0, event.cpu_time
    assert_equal 0.0, event.gc_time
    assert_equal 0, event.allocations
  end

  def teardown
    verbose = $VERBOSE
    $VERBOSE = nil
    Process.define_singleton_method(:clock_gettime, ORIGINAL_PROCESS_CLOCK_GETTIME)
    GC.define_singleton_method(:respond_to?, ORIGINAL_GC_RESPOND_TO)
    GC.define_singleton_method(:stat, ORIGINAL_GC_STAT)

    Coverage.suspend
    load INSTRUMENTER_PATH
    Coverage.resume
    $VERBOSE = verbose
  end
end
