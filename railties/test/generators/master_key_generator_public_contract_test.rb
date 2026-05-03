# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/rails/master_key/master_key_generator"

class MasterKeyGeneratorPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper
  tests Rails::Generators::MasterKeyGenerator

  setup :prepare_destination

  def in_destination
    Dir.chdir(destination_root) { yield }
  end

  test "adds master key file with user-facing guidance" do
    in_destination do
      output = capture(:stdout) { generator.add_master_key_file }

      assert_file "config/master.key"
      assert_equal 32, File.read("config/master.key").length
      assert_includes output, "Adding config/master.key to store the master encryption key:"
      assert_includes output, "Save this in a password manager your team can access."
    end
  end

  test "does not overwrite existing master key file" do
    in_destination do
      FileUtils.mkdir_p("config")
      File.write("config/master.key", "existing-key")

      output = capture(:stdout) { generator.add_master_key_file }

      assert_equal "existing-key", File.read("config/master.key")
      assert_empty output
    end
  end

  test "silent add delegates to encryption key file generator" do
    in_destination do
      generator.add_master_key_file_silently("known-key")

      assert_equal "known-key", File.read("config/master.key")
      assert_equal 0600, File.stat("config/master.key").mode & 0777
    end
  end

  test "silent add does not overwrite existing master key file" do
    in_destination do
      FileUtils.mkdir_p("config")
      File.write("config/master.key", "existing-key")

      generator.add_master_key_file_silently("new-key")

      assert_equal "existing-key", File.read("config/master.key")
    end
  end
end
