# frozen_string_literal: true

require "cases/encryption/helper"

class ActiveRecord::EncryptionTest < ActiveRecord::EncryptionTestCase
  test ".eager_load! eager loads encryption namespace and nested cipher namespace" do
    cipher_eager_loaded = false

    result = ActiveRecord::Encryption::Cipher.stub(:eager_load!, -> { cipher_eager_loaded = true }) do
      ActiveRecord::Encryption.eager_load!
    end

    assert_equal true, result
    assert cipher_eager_loaded
    assert ActiveRecord::Encryption.const_defined?(:Config, false)
    assert ActiveRecord::Encryption.const_defined?(:Encryptor, false)
  end
end
