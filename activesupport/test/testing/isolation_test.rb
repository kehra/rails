# frozen_string_literal: true

require_relative "../abstract_unit"
require "tempfile"

class IsolationTest < ActiveSupport::TestCase
  class FakeResultTest < ActiveSupport::TestCase
    def test_pass
      assert true
    end
  end

  test "forking_env reflects NO_FORK and fork availability" do
    old_no_fork = ENV.delete("NO_FORK")
    assert_equal Process.respond_to?(:fork), ActiveSupport::Testing::Isolation.forking_env?

    ENV["NO_FORK"] = "1"
    assert_not ActiveSupport::Testing::Isolation.forking_env?
  ensure
    ENV["NO_FORK"] = old_no_fork
  end

  test "run returns isolated result on success" do
    klass = Class.new(ActiveSupport::TestCase) do
      include ActiveSupport::Testing::Isolation
      def run_in_isolation
        yield
        status = Object.new
        def status.success?; true; end
        [status, Marshal.dump(Minitest::Result.from(self))]
      end
    end

    result = klass.new(:test_pass).run
    assert_instance_of Minitest::Result, result
  end

  test "run records unexpected error on isolated crash" do
    status = Object.new
    def status.success?; false; end
    def status.inspect; "failed"; end

    klass = Class.new(ActiveSupport::TestCase) do
      include ActiveSupport::Testing::Isolation
      define_method(:run_in_isolation) { [status, "boom"] }
    end

    result = klass.new(:test_pass).run
    assert_equal 1, result.failures.size
    assert_match "Subprocess exited with an error", result.failures.first.error.message
  end

  test "run records unexpected error when isolated status is nil" do
    klass = Class.new(ActiveSupport::TestCase) do
      include ActiveSupport::Testing::Isolation
      def run_in_isolation
        [nil, "boom"]
      end
    end

    result = klass.new(:test_pass).run
    assert_equal 1, result.failures.size
  end

  test "forking run_in_isolation marshals result through pipe" do
    instance = FakeResultTest.new(:test_pass)
    instance.extend ActiveSupport::Testing::Isolation::Forking
    instance.define_singleton_method(:fork) { |&block| catch(:exit) { block.call }; 123 }
    instance.define_singleton_method(:exit!) { |*| throw :exit }
    fake_pipe = FakePipe.new

    IO.stub(:pipe, ->(&block) { block.call(fake_pipe.read_end, fake_pipe.write_end) }) do
      Process.stub(:wait2, [123, success_status]) do
        status, serialized = instance.run_in_isolation { Minitest::Result.from(instance) }
        assert_predicate status, :success?
        assert_instance_of Minitest::Result, Marshal.load(serialized)
      end
    end
  end

  test "forking run_in_isolation preserves marshalable failures" do
    instance = FakeResultTest.new(:test_pass)
    instance.extend ActiveSupport::Testing::Isolation::Forking
    instance.failures << Minitest::Assertion.new("marshalable")
    instance.define_singleton_method(:fork) { |&block| catch(:exit) { block.call }; 123 }
    instance.define_singleton_method(:exit!) { |*| throw :exit }
    fake_pipe = FakePipe.new

    IO.stub(:pipe, ->(&block) { block.call(fake_pipe.read_end, fake_pipe.write_end) }) do
      Process.stub(:wait2, [123, success_status]) do
        _status, serialized = instance.run_in_isolation { }
        result = Marshal.load(serialized)
        assert_equal "marshalable", result.failures.first.message
      end
    end
  end

  test "forking run_in_isolation replaces unmarshalable failures" do
    instance = FakeResultTest.new(:test_pass)
    instance.extend ActiveSupport::Testing::Isolation::Forking
    exception = Exception.new("unmarshalable")
    exception.define_singleton_method(:not_marshalable) { true }
    exception.set_backtrace(["test backtrace"])
    instance.failures << Minitest::UnexpectedError.new(exception)
    instance.define_singleton_method(:fork) { |&block| catch(:exit) { block.call }; 123 }
    instance.define_singleton_method(:exit!) { |*| throw :exit }
    fake_pipe = FakePipe.new

    IO.stub(:pipe, ->(&block) { block.call(fake_pipe.read_end, fake_pipe.write_end) }) do
      Process.stub(:wait2, [123, success_status]) do
        _status, serialized = instance.run_in_isolation { }
        result = Marshal.load(serialized)
        assert_match "unmarshalable", result.failures.first.error.message
      end
    end
  end

  test "subprocess run_in_isolation child mode writes result" do
    instance = FakeResultTest.new(:test_pass)
    instance.extend ActiveSupport::Testing::Isolation::Subprocess
    instance.define_singleton_method(:exit!) { |*| throw :exit }
    output = Tempfile.new("isolation-output")
    old_test = ENV["ISOLATION_TEST"]
    old_output = ENV["ISOLATION_OUTPUT"]
    ENV["ISOLATION_TEST"] = "1"
    ENV["ISOLATION_OUTPUT"] = output.path

    catch(:exit) do
      instance.run_in_isolation { Minitest::Result.from(instance) }
    end

    assert_instance_of Minitest::Result, Marshal.load(File.read(output.path).unpack1("m"))
  ensure
    ENV["ISOLATION_TEST"] = old_test
    ENV["ISOLATION_OUTPUT"] = old_output
    output&.close!
  end

  test "subprocess run_in_isolation parent mode reads child output" do
    instance = FakeResultTest.new(:test_pass)
    instance.extend ActiveSupport::Testing::Isolation::Subprocess

    IO.stub(:popen, ->((env, *_args)) {
      File.write(env.fetch("ISOLATION_OUTPUT"), [Marshal.dump(Minitest::Result.from(instance))].pack("m"))
      FakeChild.new
    }) do
      Process.stub(:wait2, [321, success_status]) do
        status, serialized = instance.run_in_isolation { flunk "parent branch does not yield" }
        assert_predicate status, :success?
        assert_instance_of Minitest::Result, Marshal.load(serialized)
      end
    end
  end

  test "subprocess run_in_isolation tolerates already waited child" do
    instance = FakeResultTest.new(:test_pass)
    instance.extend ActiveSupport::Testing::Isolation::Subprocess

    IO.stub(:popen, ->((env, *_args)) {
      File.write(env.fetch("ISOLATION_OUTPUT"), [Marshal.dump(Minitest::Result.from(instance))].pack("m"))
      FakeChild.new
    }) do
      Process.stub(:wait2, ->(*) { raise Errno::ECHILD }) do
        status, serialized = instance.run_in_isolation { flunk "parent branch does not yield" }
        assert_nil status
        assert_instance_of Minitest::Result, Marshal.load(serialized)
      end
    end
  end

  private
    def success_status
      Object.new.tap do |status|
        def status.success?; true; end
      end
    end

    class FakeChild
      def pid = 321
    end

    class FakePipe
      attr_reader :read_end, :write_end

      def initialize
        @buffer = +""
        @read_end = End.new(self)
        @write_end = End.new(self)
      end

      class End
        def initialize(pipe)
          @pipe = pipe
        end

        def binmode; end
        def close; end
        def puts(value) = (@pipe.buffer = value)
        def read = @pipe.buffer
      end

      attr_accessor :buffer
    end
end
