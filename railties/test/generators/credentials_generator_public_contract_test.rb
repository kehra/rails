# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/rails/credentials/credentials_generator"

class CredentialsGeneratorPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  tests Rails::Generators::CredentialsGenerator

  setup :prepare_destination

  def setup
    super
    FileUtils.mkdir_p(File.join(destination_root, "config"))
    File.write(File.join(destination_root, "config/master.key"), ActiveSupport::EncryptedFile.generate_key)
  end

  test "adds encrypted credentials file from template" do
    output = run_generator

    assert_file "config/credentials.yml.enc"
    credentials = ActiveSupport::EncryptedConfiguration.new(
      config_path: File.join(destination_root, "config/credentials.yml.enc"),
      key_path: File.join(destination_root, "config/master.key"),
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )

    assert_match(/secret_key_base: [0-9a-f]{128}/, credentials.read)
    assert_includes output, "Adding config/credentials.yml.enc to store encrypted credentials."
    assert_includes output, "The following content has been encrypted with the Rails master key:"
  end

  test "does not overwrite an existing credentials file" do
    File.write(File.join(destination_root, "config/credentials.yml.enc"), "existing")

    output = run_generator

    assert_equal "existing", File.read(File.join(destination_root, "config/credentials.yml.enc"))
    assert_empty output
  end

  test "skip secret key base omits generated secret" do
    run_generator ["config/credentials.yml.enc", "config/master.key", "--skip-secret-key-base"]

    credentials = ActiveSupport::EncryptedConfiguration.new(
      config_path: File.join(destination_root, "config/credentials.yml.enc"),
      key_path: File.join(destination_root, "config/master.key"),
      env_key: "RAILS_MASTER_KEY",
      raise_if_missing_key: true
    )

    assert_no_match(/secret_key_base:/, credentials.read)
  end
end
