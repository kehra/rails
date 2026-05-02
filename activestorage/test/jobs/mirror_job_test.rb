# frozen_string_literal: true

require "test_helper"

class ActiveStorage::MirrorJobTest < ActiveJob::TestCase
  test "mirrors through the configured blob service when supported" do
    service = Object.new
    service.define_singleton_method(:mirror) do |key, checksum:|
      @mirrored = [ key, checksum ]
    end
    service.define_singleton_method(:mirrored) { @mirrored }

    ActiveStorage::Blob.stub(:service, service) do
      ActiveStorage::MirrorJob.perform_now "abc123", checksum: "checksum"
    end

    assert_equal [ "abc123", "checksum" ], service.mirrored
  end

  test "does nothing when the configured blob service cannot mirror" do
    service = Object.new

    ActiveStorage::Blob.stub(:service, service) do
      assert_nothing_raised do
        ActiveStorage::MirrorJob.perform_now "abc123", checksum: "checksum"
      end
    end
  end
end
