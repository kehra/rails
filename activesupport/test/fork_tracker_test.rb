# frozen_string_literal: true

require_relative "abstract_unit"

class ForkTrackerTest < ActiveSupport::TestCase
  def test_after_fork_callback_runs_once_when_pid_changes
    original_pid = ActiveSupport::ForkTracker.instance_variable_get(:@pid)
    original_callbacks = ActiveSupport::ForkTracker.instance_variable_get(:@callbacks).dup
    calls = 0

    ActiveSupport::ForkTracker.instance_variable_set(:@pid, 1)
    ActiveSupport::ForkTracker.after_fork { calls += 1 }

    Process.stub(:pid, 2) do
      ActiveSupport::ForkTracker.after_fork_callback
      ActiveSupport::ForkTracker.after_fork_callback
    end

    assert_equal 1, calls
  ensure
    ActiveSupport::ForkTracker.instance_variable_set(:@pid, original_pid)
    ActiveSupport::ForkTracker.instance_variable_set(:@callbacks, original_callbacks)
  end

  def test_core_ext_triggers_after_fork_callback_in_child
    fork_target = Class.new do
      def _fork
        0
      end

      prepend ActiveSupport::ForkTracker::CoreExt
    end.new

    assert_called(ActiveSupport::ForkTracker, :after_fork_callback) do
      assert_equal 0, fork_target._fork
    end
  end

  def test_object_fork
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    assert_not respond_to?(:fork)
    pid = fork do
      read.close
      write.close
      exit!
    end

    write.close

    Process.waitpid(pid)
    assert_equal "forked", read.read
    read.close

    assert_not called
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end

  def test_object_fork_without_block
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    if pid = fork
      write.close
      Process.waitpid(pid)
      assert_equal "forked", read.read
      read.close
      assert_not called
    else
      read.close
      write.close
      exit!
    end
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end

  def test_process_fork
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    pid = Process.fork do
      read.close
      write.close
      exit!
    end

    write.close

    Process.waitpid(pid)
    assert_equal "forked", read.read
    read.close
    assert_not called
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end

  def test_process_fork_without_block
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    if pid = Process.fork
      write.close
      Process.waitpid(pid)
      assert_equal "forked", read.read
      read.close
      assert_not called
    else
      read.close
      write.close
      exit!
    end
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end

  def test_kernel_fork
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    pid = Kernel.fork do
      read.close
      write.close
      exit!
    end

    write.close

    Process.waitpid(pid)
    assert_equal "forked", read.read
    read.close
    assert_not called
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end

  def test_kernel_fork_without_block
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    if pid = Kernel.fork
      write.close
      Process.waitpid(pid)
      assert_equal "forked", read.read
      read.close
      assert_not called
    else
      read.close
      write.close
      exit!
    end
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end

  def test_basic_object_with_kernel_fork
    read, write = IO.pipe
    called = false

    handler = ActiveSupport::ForkTracker.after_fork do
      called = true
      write.write "forked"
    end

    klass = Class.new(BasicObject) do
      include ::Kernel
      def fark(&block)
        fork(&block)
      end
    end

    object = klass.new
    assert_not object.respond_to?(:fork)
    pid = object.fark do
      read.close
      write.close
      exit!
    end

    write.close

    Process.waitpid(pid)
    assert_equal "forked", read.read
    read.close

    assert_not called
  ensure
    ActiveSupport::ForkTracker.unregister(handler)
  end
end if Process.respond_to?(:fork)
