# frozen_string_literal: true

require "test_helper"
require "active_storage/service/gcs_service"

class ActiveStorage::Service::GCSServiceUnitTest < ActiveSupport::TestCase
  class GCSDownload
    attr_reader :string

    def initialize(string)
      @string = string.dup
    end
  end

  class GCSFile
    attr_reader :updates, :deleted
    attr_accessor :content_type, :content_disposition, :metadata, :present, :size

    def initialize(data: "data")
      @data = data
      @present = true
      @size = data.bytesize
      @updates = []
    end

    def download(range: nil)
      if range
        GCSDownload.new(@data.byteslice(range))
      else
        GCSDownload.new(@data)
      end
    end

    def update
      yield self
      @updates << [ content_type, content_disposition, metadata ]
      self
    end

    def delete
      raise Google::Cloud::NotFoundError.new("missing") if @missing_on_delete
      @deleted = true
    end

    def missing_on_delete!
      @missing_on_delete = true
    end

    def exists?
      present
    end

    def present?
      present
    end

    def signed_url(**args)
      @signed_args = args
      "https://gcs.example/signed"
    end

    def signed_args
      @signed_args
    end

    def public_url
      "https://gcs.example/public"
    end
  end

  class GCSFiles
    def initialize(files)
      @files = files
    end

    def all
      @files.each { |file| yield file }
    end
  end

  class GCSBucket
    attr_reader :created, :compose_calls, :signed_calls, :files_calls
    attr_accessor :raise_invalid

    def initialize(file)
      @file = file
      @created = []
      @compose_calls = []
      @signed_calls = []
      @files_calls = []
    end

    def create_file(io, key, **options)
      raise Google::Cloud::InvalidArgumentError.new("bad") if raise_invalid
      @created << [ io.read, key, options ]
      @file
    end

    def file(_key, skip_lookup: true)
      @file
    end

    def files(prefix:)
      @files_calls << prefix
      GCSFiles.new([ @file ])
    end

    def signed_url(key, **args)
      @signed_calls << [ key, args ]
      "https://gcs.example/direct"
    end

    def compose(source_keys, destination_key)
      @compose_calls << [ source_keys, destination_key ]
      @file
    end
  end

  class GCSClient
    def initialize(bucket)
      @bucket = bucket
    end

    def bucket(name, skip_lookup: true)
      @bucket_name = name
      @skip_lookup = skip_lookup
      @bucket
    end

    attr_reader :bucket_name, :skip_lookup
  end

  test "initializes lazily and generates upload metadata" do
    service = ActiveStorage::Service::GCSService.new(bucket: "bucket", cache_control: "public", public: true)
    assert_predicate service, :public?

    file = GCSFile.new
    bucket = GCSBucket.new(file)
    client = GCSClient.new(bucket)
    service.instance_variable_set(:@client, client)

    assert_same bucket, service.bucket
    assert_equal "bucket", client.bucket_name
    assert_same client, service.client

    service.upload("key", StringIO.new("payload"), checksum: "checksum", content_type: "text/plain", disposition: :attachment, filename: ActiveStorage::Filename.new("x.txt"), custom_metadata: { color: "blue" })
    assert_equal "payload", bucket.created.last.first
    assert_equal "checksum", bucket.created.last.last[:md5]
    assert_equal "public", bucket.created.last.last[:cache_control]
    assert_equal "blue", bucket.created.last.last[:metadata][:color]
    assert_match(/attachment/, bucket.created.last.last[:content_disposition])

    service.update_metadata("key", content_type: "image/png", disposition: :inline, filename: ActiveStorage::Filename.new("x.png"), custom_metadata: { size: "small" })
    assert_equal "image/png", file.updates.last[0]
    assert_match(/inline/, file.updates.last[1])
    assert_equal({ size: "small" }, file.updates.last[2])

    headers = service.headers_for_direct_upload("key", checksum: "checksum", filename: ActiveStorage::Filename.new("x.txt"), disposition: :attachment, custom_metadata: { color: "blue" })
    assert_equal "checksum", headers["Content-MD5"]
    assert_equal "blue", headers["x-goog-meta-color"]
    assert_equal "public", headers["Cache-Control"]
    assert_match(/attachment/, headers["Content-Disposition"])

    service_without_cache_control = ActiveStorage::Service::GCSService.new(bucket: "bucket")
    service_without_cache_control.instance_variable_set(:@bucket, bucket)
    service_without_cache_control.update_metadata("key", content_type: "text/plain")
    assert_equal "text/plain", file.updates.last[0]
    plain_headers = service_without_cache_control.headers_for_direct_upload("key", checksum: "checksum")
    assert_nil plain_headers["Content-Disposition"]
    assert_nil plain_headers["Cache-Control"]
  end

  test "downloads, deletes, existence, URLs, and compose use bucket files" do
    file = GCSFile.new(data: "hello world")
    bucket = GCSBucket.new(file)
    service = ActiveStorage::Service::GCSService.new(bucket: "bucket")
    service.instance_variable_set(:@bucket, bucket)

    assert_equal "hello world", service.download("key")
    assert_equal "hello", service.download_chunk("key", 0..4)
    chunks = []
    service.download("key") { |chunk| chunks << chunk }
    assert_equal [ "hello world" ], chunks

    assert service.exist?("key")
    service.delete("key")
    assert file.deleted
    service.delete_prefixed("prefix")
    assert_equal [ "prefix" ], bucket.files_calls

    assert_equal "https://gcs.example/signed", service.url("key", expires_in: 60, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain")
    service.instance_variable_set(:@public, true)
    assert_equal "https://gcs.example/public", service.url("key", expires_in: 60, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain")

    assert_equal "https://gcs.example/direct", service.url_for_direct_upload("key", expires_in: 60, checksum: "checksum", custom_metadata: { color: "blue" })
    assert_equal "checksum", bucket.signed_calls.last.last[:content_md5]
    assert_equal "blue", bucket.signed_calls.last.last[:headers]["x-goog-meta-color"]

    service.compose([ "a", "b" ], "destination", filename: ActiveStorage::Filename.new("x.txt"), content_type: "text/plain", disposition: :attachment, custom_metadata: { color: "blue" })
    assert_equal [[ "a", "b" ], "destination"], bucket.compose_calls.last
    assert_equal({ color: "blue" }, file.updates.last[2])

    service.compose([ "a" ], "destination", content_type: "text/plain")
    assert_equal "text/plain", file.updates.last[0]
  end

  test "errors and IAM signing branches" do
    file = GCSFile.new(data: "hello")
    bucket = GCSBucket.new(file)
    service = ActiveStorage::Service::GCSService.new(bucket: "bucket", iam: true, gsa_email: "service@example.com", cache_control: "public")
    service.instance_variable_set(:@bucket, bucket)

    iam_client = Object.new
    response = Struct.new(:signed_blob).new("signed")
    iam_client.define_singleton_method(:sign_service_account_blob) { |_resource, _request| response }
    service.instance_variable_set(:@iam_client, iam_client)

    assert_equal "https://gcs.example/direct", service.url_for_direct_upload("key", expires_in: 60, checksum: "checksum")
    assert_equal :v4, bucket.signed_calls.last.last[:version]
    assert_equal "service@example.com", bucket.signed_calls.last.last[:issuer]
    assert_equal "signed", bucket.signed_calls.last.last[:signer].call("payload")

    assert_equal "https://gcs.example/signed", service.url("key", expires_in: 60, filename: ActiveStorage::Filename.new("x.txt"), disposition: :inline, content_type: "text/plain")
    assert_equal "service@example.com", file.signed_args[:issuer]
    assert_equal "signed", file.signed_args[:signer].call("payload")

    fresh_service = ActiveStorage::Service::GCSService.new(bucket: "bucket")
    Google::Auth.stub(:get_application_default, "authorization") do
      assert_equal "authorization", fresh_service.iam_client.authorization
    end

    rescue_service = ActiveStorage::Service::GCSService.new(bucket: "bucket")
    Google::Auth.stub(:get_application_default, ->(*) { raise "no credentials" }) do
      assert_nil rescue_service.iam_client.authorization
    end

    env_without_metadata = Object.new
    env_without_metadata.define_singleton_method(:metadata?) { false }
    Google::Cloud.stub(:env, env_without_metadata) do
      assert_raises(ActiveStorage::Service::GCSService::MetadataServerNotFoundError) { service.send(:email_from_metadata_server) }
    end

    env_without_email = Object.new
    env_without_email.define_singleton_method(:metadata?) { true }
    env_without_email.define_singleton_method(:lookup_metadata) { |*, **| "" }
    Google::Cloud.stub(:env, env_without_email) do
      assert_raises(ActiveStorage::Service::GCSService::MetadataServerError) { service.send(:email_from_metadata_server) }
    end

    env_with_email = Object.new
    env_with_email.define_singleton_method(:metadata?) { true }
    env_with_email.define_singleton_method(:lookup_metadata) { |*, **| "metadata@example.com" }
    Google::Cloud.stub(:env, env_with_email) do
      assert_equal "metadata@example.com", service.send(:email_from_metadata_server)
    end

    bucket.raise_invalid = true
    service.stub(:bucket, bucket) do
      assert_raises(ActiveStorage::IntegrityError) do
        service.upload("key", StringIO.new("payload"), checksum: "checksum")
      end
    end
    bucket.raise_invalid = false

    file.define_singleton_method(:download) { |**| raise Google::Cloud::NotFoundError.new("missing") }
    assert_raises(ActiveStorage::FileNotFoundError) { service.download("missing") }
    assert_raises(ActiveStorage::FileNotFoundError) { service.download_chunk("missing", 0..1) }

    file.missing_on_delete!
    assert_nothing_raised { service.delete("missing") }
    assert_nothing_raised { service.delete_prefixed("prefix") }

    file.present = false
    assert_raises(ActiveStorage::FileNotFoundError) { service.download("missing") { |_| } }
  end
end
