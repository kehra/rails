# frozen_string_literal: true

require "test_helper"
require "database/setup"
require "active_support/testing/method_call_assertions"

class ActiveStorage::BlobTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::MethodCallAssertions
  include ActiveJob::TestHelper

  test "unattached scope" do
    [ create_blob(filename: "funky.jpg"), create_blob(filename: "town.jpg") ].tap do |blobs|
      User.create! name: "DHH", avatar: blobs.first
      assert_includes ActiveStorage::Blob.unattached, blobs.second
      assert_not_includes ActiveStorage::Blob.unattached, blobs.first

      User.create! name: "Jason", avatar: blobs.second
      assert_not_includes ActiveStorage::Blob.unattached, blobs.second
    end
  end

  test "create_and_upload does not permit a conflicting blob key to overwrite an existing object" do
    data = "First file"
    blob = create_blob data: data

    assert_raises ActiveRecord::RecordNotUnique do
      ActiveStorage::Blob.stub :generate_unique_secure_token, blob.key do
        create_blob data: "This would overwrite"
      end
    end

    assert_equal data, blob.download
  end

  test "create_and_upload sets byte size and checksum" do
    data = "Hello world!"
    blob = create_blob data: data

    assert_equal data, blob.download
    assert_equal data.length, blob.byte_size
    assert_equal OpenSSL::Digest::MD5.base64digest(data), blob.checksum
  end

  test "create_and_upload extracts content type from data" do
    blob = create_file_blob fixture: "racecar.jpg", content_type: "application/octet-stream", filename: "spoofed.txt"
    assert_equal "image/jpeg", blob.content_type
  end

  test "create_and_upload prefers given content type over filename" do
    blob = create_blob content_type: "specific/type", filename: "file.txt"
    assert_equal "specific/type", blob.content_type
  end

  test "create_and_upload prefers filename over binary content type" do
    blob = create_blob content_type: "application/octet-stream", filename: "file.txt"
    assert_equal "text/plain", blob.content_type
  end

  test "create_and_upload extracts content type from filename" do
    blob = create_blob content_type: nil, filename: "hello.txt"
    assert_equal "text/plain", blob.content_type
  end

  test "create_and_upload extracts content_type from io when missing and identify: false" do
    blob = create_file_blob fixture: "racecar.jpg", content_type: nil, filename: "unknown", identify: false
    assert_equal "image/jpeg", blob.content_type
  end

  test "create_and_upload uses given content_type when identify: false" do
    blob = create_file_blob fixture: "racecar.jpg", content_type: "given/type", filename: "unknown", identify: false
    assert_equal "given/type", blob.content_type
  end

  test "create_and_upload generates a 28-character base36 key" do
    assert_match(/^[a-z0-9]{28}$/, create_blob.key)
  end

  test "create_and_upload accepts a custom key" do
    key  = SecureRandom.base36(28)
    data = "Hello world!"
    blob = create_blob key: key, data: data

    assert_equal key, blob.key
    assert_equal data, blob.download
  end

  test "create_and_upload! with a path traversal key raises on Disk service" do
    assert_raises ActiveStorage::InvalidKeyError do
      ActiveStorage::Blob.create_and_upload!(
        key: "../../etc/passwd",
        io: StringIO.new("malicious content"),
        filename: "exploit.txt",
        content_type: "text/plain"
      )
    end
  end

  test "create_and_upload accepts a record for overrides" do
    assert_nothing_raised do
      create_blob(record: User.new)
    end
  end

  test "create_and_upload raises for non-rewindable io" do
    assert_raises(ArgumentError) do
      ActiveStorage::Blob.create_and_upload!(io: file_fixture("racecar.jpg"), filename: "racecar.jpg")
    end
  end

  test "find signed uses blob id purpose by default and supports custom purposes" do
    blob = create_blob

    assert_equal blob, ActiveStorage::Blob.find_signed(blob.signed_id)
    assert_equal blob, ActiveStorage::Blob.find_signed!(blob.signed_id)

    custom_signed_id = blob.signed_id(purpose: :custom_blob_reference)
    assert_equal blob, ActiveStorage::Blob.find_signed(custom_signed_id, purpose: :custom_blob_reference)
    assert_raises(ActiveSupport::MessageVerifier::InvalidSignature) do
      ActiveStorage::Blob.find_signed!(custom_signed_id)
    end
  end

  test "record touched after analyze" do
    user = User.create!(
      name: "Nate",
      avatar: {
        content_type: "image/jpeg",
        filename: "racecar.jpg",
        io: file_fixture("racecar.jpg").open,
      }
    )

    assert_changes -> { user.reload.updated_at } do
      user.avatar.blob.analyze
    end
  end

  test "analyze does not bump lock_version on the attachment record" do
    user = User.create!(
      name: "Nate",
      avatar: {
        content_type: "image/jpeg",
        filename: "racecar.jpg",
        io: file_fixture("racecar.jpg").open,
      }
    )
    original_lock_version = user.reload.lock_version

    assert_changes -> { user.reload.updated_at } do
      user.avatar.blob.analyze
    end

    assert_equal original_lock_version, user.reload.lock_version
  end

  test "saving a stale-but-lock-valid record after analyze does not raise StaleObjectError" do
    user = User.create!(
      name: "Nate",
      avatar: {
        content_type: "image/jpeg",
        filename: "racecar.jpg",
        io: file_fixture("racecar.jpg").open,
      }
    )
    stale_user = User.find(user.id)

    user.avatar.blob.analyze

    assert_nothing_raised do
      stale_user.update!(name: "Nathan")
    end
  end

  test "build_after_unfurling generates a 28-character base36 key" do
    assert_match(/^[a-z0-9]{28}$/, build_blob_after_unfurling.key)
  end

  test "compose" do
    blobs = 3.times.map { create_blob(data: "123", filename: "numbers.txt", content_type: "text/plain", identify: false) }
    blob = ActiveStorage::Blob.compose(blobs, filename: "all_numbers.txt")

    assert_equal "123123123", blob.download
    assert_equal "text/plain", blob.content_type
    assert_equal blobs.first.byte_size * blobs.count, blob.byte_size
    assert_predicate(blob, :composed)
    assert_nil blob.checksum
  end

  test "compose with unpersisted blobs" do
    blobs = 3.times.map { create_blob(data: "123", filename: "numbers.txt", content_type: "text/plain", identify: false).dup }

    error = assert_raises(ActiveRecord::RecordNotSaved) do
      ActiveStorage::Blob.compose(blobs, filename: "all_numbers.txt")
    end
    assert_equal "All blobs must be persisted.", error.message
  end

  test "compose with custom key" do
    blobs = 3.times.map { create_blob(data: "123", filename: "numbers.txt", content_type: "text/plain", identify: false) }
    blob = ActiveStorage::Blob.compose(blobs, key: "custom_key", filename: "all_numbers.txt")

    assert_equal "custom_key", blob.key
    assert_equal "123123123", blob.download
  end

  test "image?" do
    blob = create_file_blob filename: "racecar.jpg"
    assert_predicate blob, :image?
    assert_not_predicate blob, :audio?
  end

  test "video?" do
    blob = create_file_blob(filename: "video.mp4", content_type: "video/mp4")
    assert_predicate blob, :video?
    assert_not_predicate blob, :audio?
  end

  test "text?" do
    blob = create_blob data: "Hello world!"
    assert_predicate blob, :text?
    assert_not_predicate blob, :audio?
  end

  test "blob type methods return false for nil content type" do
    blob = create_blob_before_direct_upload(
      filename: "unknown_file",
      byte_size: 100,
      checksum: "test_checksum",
      content_type: nil
    )

    assert_nil blob.content_type
    assert_not_predicate blob, :image?
    assert_not_predicate blob, :video?
    assert_not_predicate blob, :audio?
    assert_not_predicate blob, :text?
  end

  test "custom metadata defaults to an empty hash and can be replaced" do
    blob = create_blob

    assert_equal({}, blob.custom_metadata)

    blob.custom_metadata = { "color" => "blue" }

    assert_equal({ "color" => "blue" }, blob.custom_metadata)
    assert_equal({ "custom" => { "color" => "blue" }, "identified" => true }, blob.metadata)
  end

  test "download yields chunks" do
    blob   = create_blob data: "a" * 5.0625.megabytes
    chunks = []

    blob.download do |chunk|
      chunks << chunk
    end

    assert_equal 2, chunks.size
    assert_equal "a" * 5.megabytes, chunks.first
    assert_equal "a" * 64.kilobytes, chunks.second
  end

  test "download chunk delegates range reads to the service" do
    blob = create_blob(data: "Hello world!")

    assert_equal "Hello", blob.download_chunk(0...5)
  end

  test "open yielding with integrity" do
    create_file_blob(filename: "racecar.jpg").tap do |blob|
      blob.open do |file|
        assert_predicate file, :binmode?
        assert_equal 0, file.pos
        assert File.basename(file.path).start_with?("ActiveStorage-#{blob.id}-")
        assert file.path.end_with?(".jpg")
        assert_equal file_fixture("racecar.jpg").binread, file.read, "Expected downloaded file to match fixture file"
      end
    end
  end

  test "open returning with integrity" do
    file = nil
    create_file_blob(filename: "racecar.jpg").tap do |blob|
      file = blob.open

      assert_predicate file, :binmode?
      assert_equal 0, file.pos
      assert File.basename(file.path).start_with?("ActiveStorage-#{blob.id}-")
      assert file.path.end_with?(".jpg")
      assert_equal file_fixture("racecar.jpg").binread, file.read, "Expected downloaded file to match fixture file"
    ensure
      file&.close!
    end
  end

  test "open without integrity" do
    create_blob(data: "Hello, world!").tap do |blob|
      blob.update! checksum: OpenSSL::Digest::MD5.base64digest("Goodbye, world!")

      assert_raises ActiveStorage::IntegrityError do
        blob.open { |file| flunk "Expected integrity check to fail" }
      end
    end
  end

  test "open in a custom tmpdir" do
    create_file_blob(filename: "racecar.jpg").open(tmpdir: tmpdir = Dir.mktmpdir) do |file|
      assert_predicate file, :binmode?
      assert_equal 0, file.pos
      assert_match(/\.jpg\z/, file.path)
      assert file.path.start_with?(tmpdir)
      assert_equal file_fixture("racecar.jpg").binread, file.read, "Expected downloaded file to match fixture file"
    end
  end

  test "URLs expiring in 5 minutes" do
    blob = create_blob

    freeze_time do
      assert_equal expected_url_for(blob), blob.url
      assert_equal expected_url_for(blob, disposition: :attachment), blob.url(disposition: :attachment)
    end
  end

  test "URLs force content_type to binary and attachment as content disposition for content types served as binary" do
    blob = create_blob(content_type: "text/html")

    freeze_time do
      assert_equal expected_url_for(blob, disposition: :attachment, content_type: "application/octet-stream"), blob.url
      assert_equal expected_url_for(blob, disposition: :attachment, content_type: "application/octet-stream"), blob.url(disposition: :inline)
    end
  end

  test "URLs force attachment as content disposition when the content type is not allowed inline" do
    blob = create_blob(content_type: "application/zip")

    freeze_time do
      assert_equal expected_url_for(blob, disposition: :attachment, content_type: "application/zip"), blob.url
      assert_equal expected_url_for(blob, disposition: :attachment, content_type: "application/zip"), blob.url(disposition: :inline)
    end
  end

  test "URLs allow for custom filename" do
    blob = create_blob(filename: "original.txt")
    new_filename = ActiveStorage::Filename.new("new.txt")

    freeze_time do
      assert_equal expected_url_for(blob), blob.url
      assert_equal expected_url_for(blob, filename: new_filename), blob.url(filename: new_filename)
      assert_equal expected_url_for(blob, filename: new_filename), blob.url(filename: "new.txt")
      assert_equal expected_url_for(blob, filename: blob.filename), blob.url(filename: nil)
    end
  end

  test "URLs allow for custom options" do
    blob = create_blob(filename: "original.txt")

    arguments = [
      blob.key
    ]

    kwargs = {
      expires_in: ActiveStorage.service_urls_expire_in,
      disposition: :attachment,
      content_type: blob.content_type,
      filename: blob.filename,
      thumb_size: "300x300",
      thumb_mode: "crop"
    }
    assert_called_with(blob.service, :url, arguments, **kwargs) do
      blob.url(thumb_size: "300x300", thumb_mode: "crop")
    end
  end

  test "service url for direct upload delegates upload metadata to the service" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "hello.txt",
      byte_size: 11,
      checksum: OpenSSL::Digest::MD5.base64digest("Hello world!"),
      content_type: "text/plain",
      metadata: { custom: { "source" => "test" } }
    )

    expected_arguments = [ blob.key ]
    expected_kwargs = {
      expires_in: ActiveStorage.service_urls_expire_in,
      content_type: "text/plain",
      content_length: 11,
      checksum: blob.checksum,
      custom_metadata: { "source" => "test" }
    }

    assert_called_with(blob.service, :url_for_direct_upload, expected_arguments, **expected_kwargs) do
      blob.service_url_for_direct_upload
    end
  end

  test "service headers for direct upload delegate upload metadata to the service" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "hello.txt",
      byte_size: 11,
      checksum: OpenSSL::Digest::MD5.base64digest("Hello world!"),
      content_type: "text/plain",
      metadata: { custom: { "source" => "test" } }
    )

    expected_arguments = [ blob.key ]
    expected_kwargs = {
      filename: blob.filename,
      content_type: "text/plain",
      content_length: 11,
      checksum: blob.checksum,
      custom_metadata: { "source" => "test" }
    }

    assert_called_with(blob.service, :headers_for_direct_upload, expected_arguments, **expected_kwargs) do
      blob.service_headers_for_direct_upload
    end
  end

  test "upload unfurls metadata and uploads without unfurling again" do
    data = "Hello world!"
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "hello.txt",
      byte_size: 0,
      checksum: OpenSSL::Digest::MD5.base64digest(""),
      content_type: nil
    )

    blob.upload StringIO.new(data)

    assert_equal data, blob.download
    assert_equal data.bytesize, blob.byte_size
    assert_equal OpenSSL::Digest::MD5.base64digest(data), blob.checksum
    assert_equal "text/plain", blob.content_type
    assert_predicate blob, :identified?
  end

  test "identify persists inferred content type" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "racecar.jpg",
      byte_size: file_fixture("racecar.jpg").size,
      checksum: OpenSSL::Digest::MD5.file(file_fixture("racecar.jpg")).base64digest,
      content_type: "application/octet-stream"
    )
    blob.service.upload(blob.key, file_fixture("racecar.jpg").open, checksum: blob.checksum)

    blob.identify

    assert_equal "image/jpeg", blob.reload.content_type
    assert_predicate blob, :identified?
  end

  test "identify without saving uses an empty sample for empty blobs" do
    blob = ActiveStorage::Blob.create_before_direct_upload!(
      filename: "empty.txt",
      byte_size: 0,
      checksum: OpenSSL::Digest::MD5.base64digest(""),
      content_type: "application/octet-stream"
    )
    download_chunk_called = false
    blob.service.define_singleton_method(:download_chunk) do |*|
      download_chunk_called = true
    end

    blob.identify_without_saving

    assert_not download_chunk_called
    assert_predicate blob, :identified?
    assert_equal "text/plain", blob.content_type
  ensure
    blob&.service&.singleton_class&.remove_method(:download_chunk) if blob&.service&.singleton_class&.method_defined?(:download_chunk)
  end

  test "purge deletes file from external service" do
    blob = create_blob

    blob.purge
    assert_not ActiveStorage::Blob.service.exist?(blob.key)
  end

  test "purge deletes variants from external service with the purge_later" do
    blob = create_file_blob
    variant = blob.variant(resize_to_limit: [100, nil]).processed

    blob.purge
    assert_enqueued_with(job: ActiveStorage::PurgeJob, args: [variant.image.blob])
  end

  test "purge does nothing when attachments exist" do
    create_blob.tap do |blob|
      User.create! name: "DHH", avatar: blob
      assert_no_difference(-> { ActiveStorage::Blob.count }) { blob.purge }
      assert ActiveStorage::Blob.service.exist?(blob.key)
    end
  end

  test "purge doesn't raise when blob is not persisted" do
    build_blob_after_unfurling.tap do |blob|
      assert_nothing_raised { blob.purge }
      assert_predicate blob, :destroyed?
    end
  end

  test "uses service from blob when provided" do
    with_service("mirror") do
      blob = create_blob(filename: "funky.jpg", service_name: :local)
      assert_instance_of ActiveStorage::Service::DiskService, blob.service
    end
  end

  test "doesn't create a valid blob if service setting is nil" do
    with_service(nil) do
      assert_raises(ActiveRecord::RecordInvalid) do
        create_blob(filename: "funky.jpg")
      end
    end
  end

  test "invalidates record when provided service_name is invalid" do
    blob = create_blob(filename: "funky.jpg")
    blob.update(service_name: :unknown)

    assert_not blob.valid?
    assert_equal ["is invalid"], blob.errors[:service_name]
  end

  test "updating the content_type updates service metadata" do
    blob = directly_upload_file_blob(filename: "racecar.jpg", content_type: "application/octet-stream")

    assert_called_with(blob.service, :update_metadata, [blob.key], content_type: "image/jpeg", custom_metadata: {}) do
      blob.update!(content_type: "image/jpeg")
    end
  end

  test "updating the metadata updates service metadata" do
    blob = directly_upload_file_blob(filename: "racecar.jpg", content_type: "application/octet-stream")

    expected_arguments = [
      blob.key
    ]

    expected_kwargs = {
      content_type: "application/octet-stream",
      disposition: :attachment,
      filename: blob.filename,
      custom_metadata: { "test" => true }
    }

    assert_called_with(blob.service, :update_metadata, expected_arguments, **expected_kwargs) do
      blob.update!(metadata: { custom: { "test" => true } })
    end
  end

  test "scope_for_strict_loading adds includes only when track_variants and strict_loading_by_default" do
    assert_empty ActiveStorage::Blob.scope_for_strict_loading.includes_values

    with_strict_loading_by_default do
      assert_not_empty ActiveStorage::Blob.scope_for_strict_loading.includes_values

      without_variant_tracking do
        assert_empty ActiveStorage::Blob.scope_for_strict_loading.includes_values
      end
    end
  end

  private
    def expected_url_for(blob, disposition: :attachment, filename: nil, content_type: nil, service_name: :local)
      filename ||= blob.filename
      content_type ||= blob.content_type

      key_params = { key: blob.key, disposition: ActionDispatch::Http::ContentDisposition.format(disposition: disposition, filename: filename.sanitized), content_type: content_type, service_name: service_name }

      "https://example.com/rails/active_storage/disk/#{ActiveStorage.verifier.generate(key_params, expires_in: 5.minutes, purpose: :blob_key)}/#{filename}"
    end
end
