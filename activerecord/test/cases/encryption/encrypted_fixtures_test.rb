# frozen_string_literal: true

require "cases/encryption/helper"
require "models/book_encrypted"

class ActiveRecord::Encryption::EncryptableFixtureTest < ActiveRecord::EncryptionTestCase
  self.use_transactional_tests = false

  fixtures :encrypted_books, :encrypted_book_that_ignores_cases

  FixtureWithEncryptedAttributes = Class.new do
    prepend ActiveRecord::Encryption::EncryptedFixtures

    attr_reader :fixture, :model_class

    def initialize(fixture, model_class)
      @fixture = fixture
      @model_class = model_class
    end
  end

  ModelWithoutEncryptedAttributes = Class.new do
    def self.encrypted_attributes
    end
  end

  test "fixtures get encrypted automatically" do
    assert encrypted_books(:awdr).encrypted_attribute?(:name)
  end

  test "preserved columns due to ignore_case: true gets encrypted automatically" do
    book = encrypted_book_that_ignores_cases(:rfr)
    assert_equal "Ruby for Rails", book.name
    assert_encrypted_attribute book, :name, "Ruby for Rails"

    assert EncryptedBookThatIgnoresCase.find_by_name("Ruby for Rails")
  end

  test "fixtures are left unchanged when there is no model class" do
    fixture = { "name" => "Dune" }

    built_fixture = FixtureWithEncryptedAttributes.new(fixture, nil)

    assert_same fixture, built_fixture.fixture
    assert_equal({ "name" => "Dune" }, fixture)
  end

  test "fixtures are left unchanged when the model class has no encrypted attributes" do
    fixture = { "name" => "Dune" }

    built_fixture = FixtureWithEncryptedAttributes.new(fixture, ModelWithoutEncryptedAttributes)

    assert_same fixture, built_fixture.fixture
    assert_equal({ "name" => "Dune" }, fixture)
  end
end
