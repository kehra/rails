# frozen_string_literal: true

require "test_helper"

class ActionCable::Server::StreamEventLoopTest < ActionCable::TestCase
  FakeThread = Struct.new(:status)

  class FakeMonitor
    attr_reader :io
    attr_accessor :value, :interests

    def initialize(io)
      @io = io
      @interests = :r
    end
  end

  class FakeNIO
    attr_reader :registered, :deregistered, :wakeup_count

    def initialize
      @registered = {}
      @deregistered = []
      @wakeup_count = 0
    end

    def register(io, interests)
      @registered[io] = FakeMonitor.new(io).tap { |monitor| monitor.interests = interests }
    end

    def deregister(io)
      @deregistered << io
    end

    def wakeup
      @wakeup_count += 1
    end
  end

  class FakeIO
    attr_reader :closed

    def close
      @closed = true
    end
  end

  setup do
    @loop = ActionCable::Server::StreamEventLoop.new
    @nio = FakeNIO.new
    @loop.instance_variable_set(:@nio, @nio)
    @loop.instance_variable_set(:@thread, FakeThread.new("sleep"))
  end

  test "attach registers io and stores stream" do
    io = FakeIO.new
    stream = Object.new

    @loop.attach(io, stream)
    drain_todo

    monitor = @nio.registered.fetch(io)
    assert_equal :r, monitor.interests
    assert_same stream, monitor.value
    assert_equal 1, @nio.wakeup_count
  end

  test "detach deregisters io and closes it" do
    io = FakeIO.new

    @loop.detach(io, Object.new)
    drain_todo

    assert_equal [ io ], @nio.deregistered
    assert_predicate io, :closed
    assert_equal 1, @nio.wakeup_count
  end

  test "writes_pending marks registered io writable" do
    io = FakeIO.new
    @loop.attach(io, Object.new)
    drain_todo

    @loop.writes_pending(io)
    drain_todo

    assert_equal :rw, @nio.registered.fetch(io).interests
  end

  test "writes_pending ignores unknown io" do
    @loop.writes_pending(FakeIO.new)

    drain_todo

    assert_empty @nio.registered
  end

  test "stop marks loop stopping and wakes selector" do
    @loop.stop

    assert @loop.instance_variable_get(:@stopping)
    assert_equal 1, @nio.wakeup_count
  end

  test "stop without selector only marks stopping" do
    loop = ActionCable::Server::StreamEventLoop.new

    loop.stop

    assert loop.instance_variable_get(:@stopping)
  end

  private
    def drain_todo
      todo = @loop.instance_variable_get(:@todo)
      todo.pop.call until todo.empty?
    end
end
