# frozen_string_literal: true

require_relative "../abstract_unit"
require "active_support/testing/stream"

class StreamTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::Stream

  test "capture returns written stream content" do
    output = capture(:stdout) do
      puts "hello stream"
    end

    assert_equal "hello stream\n", output
  end

  test "capture restores stream after exceptions" do
    assert_raises(RuntimeError) do
      capture(:stderr) do
        warn "before boom"
        raise "boom"
      end
    end

    assert STDERR.sync
  end

  test "silence_stream suppresses output and restores stream" do
    path = Tempfile.new("stream-test").tap(&:close).path
    stream = File.open(path, "w")

    silence_stream(stream) do
      assert_equal IO::NULL, stream.path
      stream.write "hidden"
    end

    assert_equal path, stream.path
  ensure
    stream&.close
    File.unlink(path) if path && File.exist?(path)
  end

  test "quietly suppresses stdout and stderr" do
    quietly do
      puts "hidden stdout"
      warn "hidden stderr"
    end

    assert true
  end
end
