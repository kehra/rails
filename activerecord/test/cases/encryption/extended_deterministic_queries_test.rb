# frozen_string_literal: true

require "cases/encryption/helper"
require "models/book_encrypted"
require "active_support/core_ext/object/with"

class ActiveRecord::Encryption::ExtendedDeterministicQueriesTest < ActiveRecord::EncryptionTestCase
  setup do
    ActiveRecord::Encryption.config.support_unencrypted_data = true
  end

  test "Finds records when data is unencrypted" do
    UnencryptedBook.create!(name: "Dune")
    assert EncryptedBook.find_by(name: "Dune") # core
    assert EncryptedBook.where("id > 0").find_by(name: "Dune") # relation
  end

  test "Finds records when data is encrypted" do
    EncryptedBook.create!(name: "Dune")
    assert EncryptedBook.find_by(name: "Dune") # core
    assert EncryptedBook.where("id > 0").find_by(name: "Dune") # relation
  end

  test "Works well with downcased attributes" do
    EncryptedBookWithDowncaseName.create! name: "Dune"
    assert EncryptedBookWithDowncaseName.find_by(name: "DUNE")
  end

  test "Works well with string attribute names" do
    UnencryptedBook.create! "name" => "Dune"
    assert EncryptedBook.find_by("name" => "Dune")
  end

  test "find_or_create_by works" do
    EncryptedBook.find_or_create_by!(name: "Dune")
    assert EncryptedBook.find_by(name: "Dune")

    EncryptedBook.find_or_create_by!(name: "Dune")
    assert EncryptedBook.find_by(name: "Dune")
  end

  test "does not mutate arguments" do
    props = { name: "Dune" }

    assert_equal "Dune", EncryptedBook.find_or_initialize_by(props).name
    assert_equal "Dune", props[:name]
  end

  test "where(...).first_or_create works" do
    EncryptedBook.where(name: "Dune").first_or_create
    assert EncryptedBook.exists?(name: "Dune")
  end

  test "exists?(...) works" do
    EncryptedBook.create! name: "Dune"
    assert EncryptedBook.exists?(name: "Dune")
  end

  test "where leaves additional encrypted values in arrays untouched" do
    type = EncryptedBook.type_for_attribute(:name)
    additional_value = ActiveRecord::Encryption::ExtendedDeterministicQueries::AdditionalValue.new("Dune", type.previous_types.first)

    processed_arguments = ActiveRecord::Encryption::ExtendedDeterministicQueries::EncryptedQuery.process_arguments(
      EncryptedBook,
      [{ name: [additional_value, "Dune"] }],
      true
    )

    values = processed_arguments.first["name"]
    assert_same additional_value, values.first
    assert values[1..].any? { |value| value.is_a?(ActiveRecord::Encryption::ExtendedDeterministicQueries::AdditionalValue) }
  end

  test "query argument processing leaves non string values untouched" do
    processed_arguments = ActiveRecord::Encryption::ExtendedDeterministicQueries::EncryptedQuery.process_arguments(
      EncryptedBook,
      [{ name: 42 }],
      true
    )

    assert_equal 42, processed_arguments.first["name"]
  end

  test "query argument processing normalizes array keys" do
    processed_arguments = ActiveRecord::Encryption::ExtendedDeterministicQueries::EncryptedQuery.process_arguments(
      EncryptedBook,
      [{ [:name, :format] => ["Dune", "paperback"] }],
      true
    )

    assert_equal ["name", "format"], processed_arguments.first.keys.first
  end

  test "query argument processing returns original arguments without deterministic encrypted attributes" do
    owner = Class.new do
      def self.deterministic_encrypted_attributes
        []
      end
    end
    arguments = [{ name: "Dune" }]

    assert_same arguments, ActiveRecord::Encryption::ExtendedDeterministicQueries::EncryptedQuery.process_arguments(owner, arguments, true)
  end

  test "scope_for_create falls back to regular scope attributes without deterministic attributes" do
    assert_equal({ "name" => "Dune" }, UnencryptedBook.where(name: "Dune").scope_for_create)
  end

  test "If support_unencrypted_data is opted out at the attribute level, cannot find unencrypted data" do
    UnencryptedBook.create! name: "Dune"
    assert_nil EncryptedBookWithUnencryptedDataOptedOut.find_by(name: "Dune") # core
    assert_nil EncryptedBookWithUnencryptedDataOptedOut.where("id > 0").find_by(name: "Dune") # relation
  end

  test "If support_unencrypted_data is opted out at the attribute level, can find encrypted data" do
    EncryptedBook.create! name: "Dune"
    assert EncryptedBookWithUnencryptedDataOptedOut.find_by(name: "Dune") # core
    assert EncryptedBookWithUnencryptedDataOptedOut.where("id > 0").find_by(name: "Dune") # relation
  end

  test "If support_unencrypted_data is opted in at the attribute level, can find unencrypted data" do
    UnencryptedBook.create! name: "Dune"
    assert EncryptedBookWithUnencryptedDataOptedIn.find_by(name: "Dune") # core
    assert EncryptedBookWithUnencryptedDataOptedIn.where("id > 0").find_by(name: "Dune") # relation
  end

  test "If support_unencrypted_data is opted in at the attribute level, can find encrypted data" do
    EncryptedBook.create! name: "Dune"
    assert EncryptedBookWithUnencryptedDataOptedIn.find_by(name: "Dune") # core
    assert EncryptedBookWithUnencryptedDataOptedIn.where("id > 0").find_by(name: "Dune") # relation
  end

  test "if support_unencrypted_data config is disabled, but support_unencrypted_data is opted in at an attribute level, can find unencrypted data" do
    ActiveRecord::Encryption.config.with(support_unencrypted_data: false) do
      UnencryptedBook.create! name: "Dune"
      assert EncryptedBookWithUnencryptedDataOptedIn.find_by(name: "Dune") # core
      assert EncryptedBookWithUnencryptedDataOptedIn.where("id > 0").find_by(name: "Dune") # relation
    end
  end

  test "if support_unencrypted_data config is disabled, but support_unencrypted_data is opted in at an attribute level, can find encrypted data" do
    ActiveRecord::Encryption.config.with(support_unencrypted_data: false) do
      EncryptedBook.create! name: "Dune"
      assert EncryptedBookWithUnencryptedDataOptedIn.find_by(name: "Dune") # core
      assert EncryptedBookWithUnencryptedDataOptedIn.where("id > 0").find_by(name: "Dune") # relation
    end
  end
end
