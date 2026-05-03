# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/rails/encryption_key_file/encryption_key_file_generator"

class EncryptionKeyFileGeneratorPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  tests Rails::Generators::EncryptionKeyFileGenerator

  setup :prepare_destination

  def in_destination
    Dir.chdir(destination_root) { yield }
  end

  test "add key file creates key and appends gitignore entry" do
    in_destination do
      File.write(".gitignore", "/log/*\n")

      output = capture(:stdout) { generator.add_key_file("config/master.key") }

      assert_file "config/master.key"
      assert_equal 32, File.read(File.join(destination_root, "config/master.key")).length
      assert_match(/Adding config\/master.key to store the encryption key:/, output)
      assert_match(%r{/config/\*.key}, File.read(".gitignore"))
    end
  end

  test "add key file does not overwrite existing key" do
    in_destination do
      FileUtils.mkdir_p("config")
      File.write("config/master.key", "existing-key")

      output = capture(:stdout) { generator.add_key_file("config/master.key") }

      assert_equal "existing-key", File.read("config/master.key")
      assert_empty output
    end
  end

  test "silent key file creation uses provided key and avoids duplicate ignore entries" do
    in_destination do
      File.write(".gitignore", "")

      generator.add_key_file_silently("config/master.key", "known-key")
      generator.add_key_file_silently("config/credentials/production.key", "prod-key")
      generator.ensure_key_files_are_ignored_silently("config/master.key")

      assert_equal "known-key", File.read("config/master.key")
      assert_equal "prod-key", File.read("config/credentials/production.key")
      assert_equal 1, File.read(".gitignore").scan(%r{/config/\*.key}).length
      assert_match %r{/config/credentials/\*.key}, File.read(".gitignore")
    end
  end

  test "ensure key files are ignored appends and logs when gitignore exists" do
    in_destination do
      File.write(".gitignore", "/log/*\n")

      output = capture(:stdout) { generator.ensure_key_files_are_ignored("config/master.key") }

      assert_includes output, "Ignoring"
      assert_match %r{/config/\*.key}, File.read(".gitignore")
    end
  end

  test "silent ignore is a no-op when gitignore is absent" do
    in_destination do
      generator.ensure_key_files_are_ignored_silently("config/master.key")

      assert_no_file ".gitignore"
    end
  end

  test "ensure key files are ignored reports manual instruction when gitignore is absent" do
    in_destination do
      output = capture(:stdout) { generator.ensure_key_files_are_ignored("config/master.key") }

      assert_includes output, "IMPORTANT: Don't commit config/master.key. Add this to your ignore file:"
      assert_includes output, "/config/*.key"
    end
  end
end
