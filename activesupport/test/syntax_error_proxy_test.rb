# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/syntax_error_proxy"

class SyntaxErrorProxyTest < ActiveSupport::TestCase
  test "backtrace prepends parsed syntax error message" do
    error = SyntaxError.new("/tmp/example.rb:1: syntax error, unexpected end-of-input")
    error.set_backtrace(["caller.rb:2:in `load'"])
    proxy = ActiveSupport::SyntaxErrorProxy.new(error)

    assert_equal ["/tmp/example.rb:1: syntax error, unexpected end-of-input", "caller.rb:2:in `load'"], proxy.backtrace
  end

  test "backtrace locations include parsed message and wrapped original locations" do
    begin
      eval("def broken", binding, "/tmp/syntax_error_proxy_test.rb", 12)
    rescue SyntaxError => error
      proxy = ActiveSupport::SyntaxErrorProxy.new(error)
      locations = proxy.backtrace_locations

      assert_equal "/tmp/syntax_error_proxy_test.rb", locations.first.path
      assert_equal 12, locations.first.lineno
      assert_match(/syntax_error_proxy_test\.rb:12:/, locations.first.to_s)
      assert_equal "/tmp/syntax_error_proxy_test.rb", locations.first.absolute_path
      assert_nil locations.first.spot(nil)
      assert_nil locations.first.label
      assert_nil locations.first.base_label
      location_proxy = locations.find { |location| location.is_a?(ActiveSupport::SyntaxErrorProxy::BacktraceLocationProxy) }
      assert location_proxy
      assert_raises(NoMethodError) { location_proxy.spot(nil) }
    end
  end

  test "eval syntax errors use the original backtrace location" do
    error = SyntaxError.new("(eval):1: syntax error, unexpected end-of-input")
    error.set_backtrace(["caller.rb:1:in `eval'"])
    error.define_singleton_method(:backtrace_locations) { caller_locations }
    proxy = ActiveSupport::SyntaxErrorProxy.new(error)

    assert_match(%r{active_support/syntax_error_proxy\.rb:\d+: \(eval\):1:}, proxy.backtrace.first)
  end

  test "backtrace locations return nil when original locations are nil" do
    error = SyntaxError.new("plain message")
    error.define_singleton_method(:backtrace_locations) { nil }
    proxy = ActiveSupport::SyntaxErrorProxy.new(error)

    assert_nil proxy.backtrace_locations
  end

  test "backtrace locations keep unparsable trace strings" do
    error = SyntaxError.new("plain message")
    error.define_singleton_method(:backtrace_locations) { caller_locations }
    proxy = ActiveSupport::SyntaxErrorProxy.new(error)

    location = proxy.backtrace_locations.first
    assert_equal "plain message", location.path
    assert_equal 0, location.lineno
    assert_equal "plain message", location.to_s
  end
end
