# frozen_string_literal: true

require "test_helper"

class ActiveStorage::ServiceTest < ActiveSupport::TestCase
  class FakeService < ActiveStorage::Service
    attr_reader :uploaded

    def initialize(public: false)
      @public = public
      @uploaded = {}
    end

    def upload(key, io, checksum: nil, **options)
      @uploaded[key] = io.read
    end

    def download(key)
      if block_given?
        yield @uploaded.fetch(key)
      else
        @uploaded.fetch(key)
      end
    end

    def private_url(key, **)
      "private://#{key}"
    end

    def public_url(key, **)
      "public://#{key}"
    end
  end

  test "inspect attributes" do
    config = {
      local: { service: "Disk", root: "/tmp/active_storage_service_test" },
      tmp: { service: "Disk", root: "/tmp/active_storage_service_test_tmp" },
    }

    service = ActiveStorage::Service.configure(:local, config)
    assert_match(/#<ActiveStorage::Service::DiskService name=:local>/, service.inspect)

    service = ActiveStorage::Service.new
    assert_match(/#<ActiveStorage::Service>/, service.inspect)
  end

  test "abstract service methods raise not implemented" do
    service = ActiveStorage::Service.new

    assert_raises(NotImplementedError) { service.upload("key", StringIO.new("data")) }
    assert_raises(NotImplementedError) { service.download("key") }
    assert_raises(NotImplementedError) { service.download_chunk("key", 0..1) }
    assert_raises(NotImplementedError) { service.compose([ "a" ], "b") }
    assert_raises(NotImplementedError) { service.delete("key") }
    assert_raises(NotImplementedError) { service.delete_prefixed("prefix") }
    assert_raises(NotImplementedError) { service.exist?("key") }
    assert_raises(NotImplementedError) { service.url_for_direct_upload("key", expires_in: 1.minute, content_type: "text/plain", content_length: 1, checksum: "checksum") }
    assert_raises(NotImplementedError) { service.send(:private_url, "key", expires_in: 1.minute, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain") }
    assert_raises(NotImplementedError) { service.send(:public_url, "key") }
    assert_raises(NotImplementedError) { service.send(:custom_metadata_headers, {}) }
  end

  test "default metadata and direct upload headers are empty" do
    service = FakeService.new

    assert_nil service.update_metadata("key", identified: true)
    assert_equal({}, service.headers_for_direct_upload("key", filename: "x.txt", content_type: "text/plain", content_length: 1, checksum: "checksum"))
  end

  test "url dispatches to public or private url" do
    assert_equal "private://key", FakeService.new.url("key", expires_in: 1.minute, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain")
    assert_equal "public://key", FakeService.new(public: true).url("key", expires_in: 1.minute, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain")
  end

  test "checksum supports rewindable io, file io, no chunking, and rejects non-rewindable io" do
    service = ActiveStorage::Service.new
    io = StringIO.new("checksum data")

    assert_equal OpenSSL::Digest::MD5.base64digest("checksum data"), service.compute_checksum(io)
    assert_equal 0, io.pos

    Tempfile.create("checksum") do |file|
      file.binmode
      file.write("checksum data")
      file.rewind

      assert_equal OpenSSL::Digest::MD5.file(file).base64digest, service.compute_checksum(file)
    end

    service.stub(:default_chunk_size, 0) do
      assert_equal OpenSSL::Digest::MD5.base64digest("checksum data"), service.compute_checksum(StringIO.new("checksum data"))
    end

    assert_raises(ArgumentError) { service.compute_checksum(Object.new) }
  end

  test "open returns or yields a verified tempfile" do
    service = FakeService.new
    checksum = OpenSSL::Digest::MD5.base64digest("downloaded")
    service.upload("key", StringIO.new("downloaded"))

    tempfile = service.open("key", checksum: checksum)
    assert_equal "downloaded", tempfile.read
    tempfile.close!

    yielded_path = nil
    service.open("key", checksum: checksum) do |file|
      yielded_path = file.path
      assert_equal "downloaded", file.read
    end

    assert_not File.exist?(yielded_path)
    assert_raises(ActiveStorage::IntegrityError) { service.open("key", checksum: "bad") }

    tempfile = service.open("key", checksum: "bad", verify: false)
    assert_equal "downloaded", tempfile.read
    tempfile.close!
  end
end
