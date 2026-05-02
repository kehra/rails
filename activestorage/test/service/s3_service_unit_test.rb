# frozen_string_literal: true

require "test_helper"
require "active_storage/service/s3_service"

class ActiveStorage::Service::S3ServiceUnitTest < ActiveSupport::TestCase
  class S3Body
    attr_reader :string

    def initialize(string)
      @string = string.dup
    end
  end

  class S3Response
    attr_reader :body

    def initialize(string)
      @body = S3Body.new(string)
    end
  end

  class S3Object
    attr_reader :puts, :deleted, :presigned, :uploaded_streams
    attr_accessor :exists, :content_length, :raise_no_such_key, :raise_bad_digest

    def initialize(data: "data")
      @data = data
      @exists = true
      @content_length = data.bytesize
      @puts = []
      @presigned = []
      @uploaded_streams = []
    end

    def get(**options)
      raise Aws::S3::Errors::NoSuchKey.new(nil, "missing") if raise_no_such_key

      if range = options[:range]
        from, to = range.delete_prefix("bytes=").split("-").map(&:to_i)
        S3Response.new(@data.byteslice(from..to))
      else
        S3Response.new(@data)
      end
    end

    def put(**options)
      @puts << options
      raise Aws::S3::Errors::BadDigest.new(nil, "bad") if raise_bad_digest
      true
    end

    def delete
      @deleted = true
    end

    def exists?
      exists
    end

    def presigned_url(method, **options)
      @presigned << [ method, options ]
      "https://s3.example/#{method}"
    end

    def public_url(**options)
      "https://public.example/#{options.inspect}"
    end

    def upload_stream(**options)
      io = StringIO.new
      yield io
      @uploaded_streams << [ io.string, options ]
    end
  end

  class S3Objects
    attr_reader :deleted_prefix

    def initialize(prefix)
      @prefix = prefix
    end

    def batch_delete!
      @deleted_prefix = @prefix
    end
  end

  class S3Bucket
    attr_reader :name, :objects_calls

    def initialize(object)
      @name = "bucket"
      @object = object
      @objects_calls = []
    end

    def object(_key)
      @object
    end

    def objects(prefix:)
      S3Objects.new(prefix).tap { |objects| @objects_calls << objects }
    end
  end

  class TransferManager
    attr_reader :uploaded_streams

    def initialize
      @uploaded_streams = []
    end

    def upload_stream(**options)
      io = StringIO.new
      yield io
      @uploaded_streams << [ io.string, options ]
    end
  end

  test "initializes bucket, digest configuration, public ACL, and direct upload helpers" do
    service = ActiveStorage::Service::S3Service.new(
      bucket: "bucket", public: true, upload: { multipart_threshold: 10, cache_control: "public" },
      default_digest_type: :sha256, region: "us-east-1", access_key_id: "x", secret_access_key: "y", stub_responses: true
    )

    assert_equal :sha256, service.default_digest_type
    assert_equal OpenSSL::Digest::SHA256, service.default_digest_class
    assert_equal 10, service.multipart_upload_threshold
    assert_equal "public-read", service.upload_options[:acl]
    assert_predicate service, :public?

    private_service = ActiveStorage::Service::S3Service.new(
      bucket: "bucket", public: false, region: "us-east-1", access_key_id: "x", secret_access_key: "y", stub_responses: true
    )
    assert_not private_service.public?
    assert_nil private_service.upload_options[:acl]
    assert_equal OpenSSL::Digest::MD5.base64digest("data"), private_service.compute_checksum(StringIO.new("data"))

    transfer_manager = Aws::S3.send(:remove_const, :TransferManager) if Aws::S3.const_defined?(:TransferManager)
    without_transfer_manager = ActiveStorage::Service::S3Service.new(
      bucket: "bucket", region: "us-east-1", access_key_id: "x", secret_access_key: "y", stub_responses: true
    )
    assert_nil without_transfer_manager.instance_variable_get(:@transfer_manager)
  ensure
    Aws::S3.const_set(:TransferManager, transfer_manager) if transfer_manager
  end

  test "direct upload helpers for sha256 checksums" do
    service = ActiveStorage::Service::S3Service.new(
      bucket: "bucket", public: true, upload: { multipart_threshold: 10, cache_control: "public" },
      default_digest_type: :sha256, region: "us-east-1", access_key_id: "x", secret_access_key: "y", stub_responses: true
    )

    assert_equal OpenSSL::Digest::SHA256, service.checksum_implementation
    assert_equal OpenSSL::Digest::MD5, service.checksum_implementation(check_digest_type: :md5)
    assert_equal OpenSSL::Digest::SHA256, service.checksum_implementation(check_digest_type: :sha256)
    assert_raises(ActiveStorage::IntegrityError) { service.checksum_implementation(check_digest_type: :sha1) }

    checksum = OpenSSL::Digest::SHA256.base64digest("data")
    assert_equal "sha256:#{checksum}", service.compute_checksum(StringIO.new("data"))

    headers = service.headers_for_direct_upload("key", content_type: "text/plain", checksum: "sha256:abc", filename: ActiveStorage::Filename.new("x.txt"), disposition: :attachment, custom_metadata: { color: "blue" })
    assert_equal "text/plain", headers["Content-Type"]
    assert_equal "abc", headers["x-amz-checksum-sha256"]
    assert_equal "blue", headers["x-amz-meta-color"]
    assert_match(/attachment/, headers["Content-Disposition"])

    md5_headers = service.headers_for_direct_upload("key", content_type: "text/plain", checksum: "md5checksum")
    assert_equal "md5checksum", md5_headers["Content-MD5"]

    no_checksum_headers = service.headers_for_direct_upload("key", content_type: "text/plain", checksum: nil)
    assert_nil no_checksum_headers["Content-MD5"]

    object = S3Object.new
    bucket = S3Bucket.new(object)
    service.instance_variable_set(:@bucket, bucket)
    assert_equal "https://s3.example/put", service.url_for_direct_upload("key", expires_in: 60, content_type: "text/plain", content_length: 4, checksum: "sha256checksum")
    assert_equal :sha256, object.presigned.last.last[:checksum_algorithm]
    assert_equal "sha256checksum", object.presigned.last.last[:checksum_sha256]
  end

  test "object operations delegate to S3 object and bucket" do
    object = S3Object.new(data: "hello world")
    bucket = S3Bucket.new(object)
    service = ActiveStorage::Service::S3Service.allocate
    service.instance_variable_set(:@bucket, bucket)
    service.instance_variable_set(:@public, false)
    service.instance_variable_set(:@default_digest_type, :md5)
    service.instance_variable_set(:@default_digest_class, OpenSSL::Digest::MD5)
    service.instance_variable_set(:@multipart_upload_threshold, 100)
    service.instance_variable_set(:@upload_options, {})

    service.upload("key", StringIO.new("small"), checksum: "checksum", filename: ActiveStorage::Filename.new("x.txt"), content_type: "text/plain", disposition: :inline, custom_metadata: { color: "blue" })
    assert_equal "text/plain", object.puts.last[:content_type]
    assert_equal "checksum", object.puts.last[:content_md5]
    assert_equal({ color: "blue" }, object.puts.last[:metadata])

    service.upload("key-without-options", StringIO.new("plain"), content_type: "text/plain")
    assert_nil object.puts.last[:content_md5]
    assert_nil object.puts.last[:content_disposition]

    assert_equal "hello world", service.download("key")
    assert_equal "hello", service.download_chunk("key", 0..4)
    assert_equal "hell", service.download_chunk("key", 0...4)
    chunks = []
    service.download("key") { |chunk| chunks << chunk }
    assert_equal [ "hello world" ], chunks

    assert service.exist?("key")
    service.delete("key")
    assert object.deleted
    service.delete_prefixed("prefix")
    assert_equal "prefix", bucket.objects_calls.last.deleted_prefix

    assert_equal "https://s3.example/put", service.url_for_direct_upload("key", expires_in: 60, content_type: "text/plain", content_length: 5, checksum: "checksum", custom_metadata: { color: "blue" })
    assert_equal "https://s3.example/get", service.url("key", expires_in: 60, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain")

    service.instance_variable_set(:@public, true)
    assert_match(%r{https://public.example/}, service.url("key", expires_in: 60, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain"))

    object.raise_no_such_key = true
    assert_raises(ActiveStorage::FileNotFoundError) { service.download("missing") }
    assert_raises(ActiveStorage::FileNotFoundError) { service.download_chunk("missing", 0..1) }
  end

  test "multipart upload and compose stream data" do
    object = S3Object.new(data: "composed")
    bucket = S3Bucket.new(object)
    service = ActiveStorage::Service::S3Service.allocate
    service.instance_variable_set(:@bucket, bucket)
    service.instance_variable_set(:@public, false)
    service.instance_variable_set(:@default_digest_type, :md5)
    service.instance_variable_set(:@default_digest_class, OpenSSL::Digest::MD5)
    service.instance_variable_set(:@multipart_upload_threshold, 1)
    service.instance_variable_set(:@upload_options, {})
    service.instance_variable_set(:@transfer_manager, nil)

    service.upload("large", StringIO.new("large data"), content_type: "text/plain")
    assert_equal "large data", object.uploaded_streams.last.first

    transfer_manager = TransferManager.new
    service.instance_variable_set(:@transfer_manager, transfer_manager)
    service.upload("large", StringIO.new("managed data"), content_type: "text/plain")
    assert_equal "managed data", transfer_manager.uploaded_streams.last.first

    service.instance_variable_set(:@transfer_manager, nil)
    service.compose([ "a", "b" ], "destination", content_type: "text/plain", custom_metadata: { color: "blue" })
    assert_equal "composedcomposed", object.uploaded_streams.last.first
    assert_equal({ color: "blue" }, object.uploaded_streams.last.last[:metadata])

    service.compose([ "a" ], "destination", filename: ActiveStorage::Filename.new("x.txt"), disposition: :attachment)
    assert_match(/attachment/, object.uploaded_streams.last.last[:content_disposition])

    object.exists = false
    assert_raises(ActiveStorage::FileNotFoundError) { service.download("missing") { |_| } }

    service.instance_variable_set(:@multipart_upload_threshold, 100)
    object.raise_bad_digest = true
    assert_raises(ActiveStorage::IntegrityError) { service.upload("bad", StringIO.new("bad"), checksum: "bad") }
  end
end
