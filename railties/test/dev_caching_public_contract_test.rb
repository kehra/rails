# frozen_string_literal: true

require "abstract_unit"
require "rails/dev_caching"

class RailsDevCachingPublicContractTest < ActiveSupport::TestCase
  setup do
    @old_pwd = Dir.pwd
    @tmp = Dir.mktmpdir("rails-dev-caching-test")
    Dir.chdir(@tmp)
  end

  teardown do
    Dir.chdir(@old_pwd)
    FileUtils.rm_rf(@tmp)
  end

  test "enable by file creates cache marker and restart marker when disabled" do
    output = capture(:stdout) { Rails::DevCaching.enable_by_file }

    assert_equal "Action Controller caching enabled for development mode.\n", output
    assert File.exist?("tmp/caching-dev.txt")
    assert File.exist?("tmp/restart.txt")
  end

  test "enable by file removes cache marker and touches restart marker when enabled" do
    FileUtils.mkdir_p("tmp")
    FileUtils.touch("tmp/caching-dev.txt")
    FileUtils.touch("tmp/restart.txt", mtime: Time.now - 60)
    previous_restart_mtime = File.mtime("tmp/restart.txt")

    output = capture(:stdout) { Rails::DevCaching.enable_by_file }

    assert_equal "Action Controller caching disabled for development mode.\n", output
    assert_not File.exist?("tmp/caching-dev.txt")
    assert_operator previous_restart_mtime, :<, File.mtime("tmp/restart.txt")
  end

  test "enable by argument creates removes or leaves cache marker" do
    Rails::DevCaching.enable_by_argument(true)
    assert File.exist?("tmp/caching-dev.txt")

    Rails::DevCaching.enable_by_argument(nil)
    assert File.exist?("tmp/caching-dev.txt")

    Rails::DevCaching.enable_by_argument(false)
    assert_not File.exist?("tmp/caching-dev.txt")

    assert_nothing_raised { Rails::DevCaching.enable_by_argument(false) }
    assert Dir.exist?("tmp")
  end
end
