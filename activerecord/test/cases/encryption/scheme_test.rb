# frozen_string_literal: true

require "cases/encryption/helper"
require "models/book"

class ActiveRecord::Encryption::SchemeTest < ActiveRecord::EncryptionTestCase
  test "validates config options when using encrypted attributes" do
    assert_invalid_declaration deterministic: false, ignore_case: true
    assert_invalid_declaration key: "1234", key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("my secret")
    assert_invalid_declaration compress: false, compressor: Zlib
    assert_invalid_declaration compressor: Zlib, encryptor: ActiveRecord::Encryption::Encryptor.new

    assert_valid_declaration deterministic: true
    assert_valid_declaration key: "1234"
    assert_valid_declaration key_provider: ActiveRecord::Encryption::DerivedSecretKeyProvider.new("my secret")
  end

  test "should create an encryptor well when compressor is given" do
    MyCompressor = Class.new do
      def self.deflate(data)
        "deflated #{data}"
      end

      def self.inflate(data)
        data.sub("deflated ", "")
      end
    end

    type = declare_encrypts_with compressor: MyCompressor

    assert_equal MyCompressor, type.scheme.to_h[:encryptor].compressor
  end

  test "should create an encryptor well when compress is false" do
    type = declare_encrypts_with compress: false

    assert_not type.scheme.to_h[:encryptor].compress?
  end

  test "exposes option predicates and hash representation" do
    scheme = ActiveRecord::Encryption::Scheme.new(
      deterministic: true,
      downcase: true,
      ignore_case: true,
      support_unencrypted_data: true,
      previous_schemes: [ ActiveRecord::Encryption::Scheme.new ],
      encryptor: ActiveRecord::Encryption::NullEncryptor.new
    )

    assert_predicate scheme, :deterministic?
    assert_predicate scheme, :downcase?
    assert_predicate scheme, :ignore_case?
    assert_predicate scheme, :support_unencrypted_data?
    assert_predicate scheme, :fixed?
    assert_equal true, scheme.to_h[:deterministic]
    assert_equal true, scheme.to_h[:downcase]
    assert_equal true, scheme.to_h[:ignore_case]
    assert_equal [ scheme.previous_schemes.first ], scheme.to_h[:previous_schemes]
    assert_instance_of ActiveRecord::Encryption::NullEncryptor, scheme.to_h[:encryptor]
  end

  test "uses config fallback for support_unencrypted_data" do
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    assert_predicate ActiveRecord::Encryption::Scheme.new, :support_unencrypted_data?
  end

  test "fixed? follows deterministic fixed option" do
    assert_predicate ActiveRecord::Encryption::Scheme.new(deterministic: { fixed: true }), :fixed?
    assert_not ActiveRecord::Encryption::Scheme.new(deterministic: { fixed: false }).fixed?
    assert_not ActiveRecord::Encryption::Scheme.new.fixed?
  end

  test "builds key providers from explicit provider key deterministic option or default context" do
    key_provider = ActiveRecord::Encryption::DerivedSecretKeyProvider.new("some secret")
    assert_same key_provider, ActiveRecord::Encryption::Scheme.new(key_provider: key_provider).key_provider

    assert_instance_of ActiveRecord::Encryption::DerivedSecretKeyProvider, ActiveRecord::Encryption::Scheme.new(key: "some secret").key_provider
    assert_instance_of ActiveRecord::Encryption::DeterministicKeyProvider, ActiveRecord::Encryption::Scheme.new(deterministic: true).key_provider
    assert_same ActiveRecord::Encryption.key_provider, ActiveRecord::Encryption::Scheme.new.key_provider
  end

  test "merges schemes with other scheme taking precedence" do
    base_scheme = ActiveRecord::Encryption::Scheme.new(deterministic: false, downcase: true)
    override_scheme = ActiveRecord::Encryption::Scheme.new(deterministic: true, ignore_case: true)
    merged_scheme = base_scheme.merge(override_scheme)

    assert_predicate merged_scheme, :deterministic?
    assert_predicate merged_scheme, :downcase?
    assert_predicate merged_scheme, :ignore_case?
  end

  test "runs blocks with and without context properties" do
    scheme_without_context = ActiveRecord::Encryption::Scheme.new
    assert_equal "plain", scheme_without_context.with_context { "plain" }

    encryptor = ActiveRecord::Encryption::NullEncryptor.new
    scheme_with_context = ActiveRecord::Encryption::Scheme.new(encryptor: encryptor)

    assert_same encryptor, scheme_with_context.with_context { ActiveRecord::Encryption.encryptor }
  end

  test "checks compatibility using deterministic option" do
    deterministic_scheme = ActiveRecord::Encryption::Scheme.new(deterministic: true)
    other_deterministic_scheme = ActiveRecord::Encryption::Scheme.new(deterministic: true)
    non_deterministic_scheme = ActiveRecord::Encryption::Scheme.new(deterministic: false)

    assert deterministic_scheme.compatible_with?(other_deterministic_scheme)
    assert_not deterministic_scheme.compatible_with?(non_deterministic_scheme)
  end

  private
    def assert_invalid_declaration(**options)
      assert_raises ActiveRecord::Encryption::Errors::Configuration do
        declare_encrypts_with(options)
      end
    end

    def assert_valid_declaration(**options)
      assert_nothing_raised do
        declare_encrypts_with(options)
      end
    end

    def declare_encrypts_with(options)
      Class.new(Book) do
        encrypts :name, **options
      end.type_for_attribute(:name)
    end
end
