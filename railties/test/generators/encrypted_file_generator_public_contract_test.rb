# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/rails/encrypted_file/encrypted_file_generator"

class EncryptedFileGeneratorPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  tests Rails::Generators::EncryptedFileGenerator

  setup :prepare_destination

  def setup
    super
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/master.key"), ActiveSupport::EncryptedFile.generate_key)
  end

  test "adds encrypted file silently using default template" do
    content_path = File.join(destination_root, "config/tokens.yml.enc")
    key_path = File.join(destination_root, "config/master.key")

    generator.add_encrypted_file_silently(content_path, key_path)

    encrypted_file = ActiveSupport::EncryptedFile.new(
      content_path: content_path,
      key_path: key_path,
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )

    assert_match(/# aws:/, encrypted_file.read)
  end

  test "adds encrypted file silently using custom template" do
    content_path = File.join(destination_root, "config/tokens.yml.enc")
    key_path = File.join(destination_root, "config/master.key")

    generator.add_encrypted_file_silently(content_path, key_path, "api_token: 123")

    encrypted_file = ActiveSupport::EncryptedFile.new(
      content_path: content_path,
      key_path: key_path,
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )

    assert_equal "api_token: 123", encrypted_file.read
  end

  test "does not overwrite existing encrypted file" do
    path = File.join(destination_root, "config/tokens.yml.enc")
    File.write(path, "existing")

    generator.add_encrypted_file_silently(path, File.join(destination_root, "config/master.key"), "new content")

    assert_equal "existing", File.read(path)
  end
end
