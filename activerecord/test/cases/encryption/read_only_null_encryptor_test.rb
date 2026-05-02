# frozen_string_literal: true

require "cases/encryption/helper"

class ActiveRecord::Encryption::ReadOnlyNullEncryptorTest < ActiveRecord::EncryptionTestCase
  setup do
    @encryptor = ActiveRecord::Encryption::ReadOnlyNullEncryptor.new
  end

  test "decrypt returns the encrypted message" do
    assert_equal "some text", @encryptor.decrypt("some text")
  end

  test "encrypt raises an Encryption" do
    assert_raises ActiveRecord::Encryption::Errors::Encryption do
      @encryptor.encrypt("some text")
    end
  end

  test "encrypted? returns false" do
    assert_not @encryptor.encrypted?("some text")
  end

  test "binary? returns false" do
    assert_not @encryptor.binary?
  end
end
