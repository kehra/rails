# frozen_string_literal: true

require "cases/encryption/helper"

class ActiveRecord::Encryption::ConfigTest < ActiveRecord::EncryptionTestCase
  setup do
    @config = ActiveRecord::Encryption::Config.new
  end

  test "initializes with encryption defaults" do
    assert_equal false, @config.store_key_references
    assert_equal false, @config.support_unencrypted_data
    assert_equal false, @config.encrypt_fixtures
    assert_equal true, @config.validate_column_size
    assert_equal true, @config.add_to_filter_parameters
    assert_equal [], @config.excluded_from_filter_parameters
    assert_equal [], @config.previous_schemes
    assert_equal Encoding::UTF_8, @config.forced_encoding_for_deterministic_encryption
    assert_equal OpenSSL::Digest::SHA1, @config.hash_digest_class
    assert_equal Zlib, @config.compressor
    assert_equal false, @config.extend_queries
  end

  test "required keys will raise a config error when accessed but not set" do
    @config.primary_key = nil
    assert_raises ActiveRecord::Encryption::Errors::Configuration do
      @config.primary_key
    end

    @config.primary_key = "some key"
    assert_nothing_raised do
      @config.primary_key
    end
  end

  test "previous= appends configured encryption schemes" do
    provider = Object.new

    @config.previous = [
      { key_provider: provider },
      { deterministic: true, key_provider: provider },
    ]

    assert_equal 2, @config.previous_schemes.length
    assert_same provider, @config.previous_schemes.first.key_provider
    assert @config.previous_schemes.second.deterministic?
  end

  test "support_sha1_for_non_deterministic_encryption adds a previous scheme when primary key is configured" do
    @config.primary_key = "a" * 32

    @config.support_sha1_for_non_deterministic_encryption = true

    assert_equal 1, @config.previous_schemes.length
    assert_instance_of ActiveRecord::Encryption::DerivedSecretKeyProvider, @config.previous_schemes.first.key_provider
  end

  test "support_sha1_for_non_deterministic_encryption is ignored without primary key or when disabled" do
    @config.support_sha1_for_non_deterministic_encryption = true
    assert_empty @config.previous_schemes

    @config.primary_key = "a" * 32
    @config.support_sha1_for_non_deterministic_encryption = false
    assert_empty @config.previous_schemes
  end
end
