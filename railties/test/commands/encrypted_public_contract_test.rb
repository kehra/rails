# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/encrypted/encrypted_command"
require "active_support/encrypted_configuration"

class EncryptedPublicContractTest < ActiveSupport::TestCase
  setup do
    @encrypted = fake_encrypted(key: true, read: "secret: value")
    @application = Object.new
    encrypted = @encrypted
    @application.define_singleton_method(:encrypted) do |content_path, key_path:|
      encrypted.requests << [content_path, key_path]
      encrypted
    end
  end

  test "edit loads environment ensures files and changes encrypted configuration" do
    command = command_for
    calls = []
    command.define_singleton_method(:load_environment_config!) { calls << :load_environment_config }
    command.define_singleton_method(:ensure_encryption_key_has_been_added) { calls << :ensure_key }
    command.define_singleton_method(:ensure_encrypted_configuration_has_been_added) { calls << :ensure_file }
    command.define_singleton_method(:change_encrypted_configuration_in_system_editor) { calls << :change }

    command.edit

    assert_equal [ :load_environment_config, :ensure_key, :ensure_file, :change ], calls
  end

  test "show loads environment and prints decrypted content or missing message" do
    command = command_for
    calls = []
    command.define_singleton_method(:load_environment_config!) { calls << :load_environment_config }
    output = with_rails_application(@application) { capture(:stdout) { command.show } }

    assert_equal [ :load_environment_config ], calls
    assert_includes output, "secret: value"

    @encrypted.read_value = nil
    command = command_for
    command.define_singleton_method(:missing_encrypted_configuration_message) { "missing config" }

    assert_equal "missing config\n", capture(:stdout) { command.show }
  end

  test "paths and encrypted configuration use arguments and key option" do
    command = command_for(["config/data.yml.enc"], ["--key=config/data.key"])

    with_rails_application(@application) do
      assert_equal "config/data.yml.enc", command.send(:content_path)
      assert_equal "config/data.key", command.send(:key_path)
      assert_same @encrypted, command.send(:encrypted_configuration)
    end

    assert_equal [["config/data.yml.enc", "config/data.key"]], @encrypted.requests
  end

  test "ensure key and encrypted file delegate to generators" do
    command = command_for
    key_generator = Object.new
    key_calls = []
    key_generator.define_singleton_method(:add_key_file) { |path| key_calls << path }
    file_generator = Object.new
    file_calls = []
    file_generator.define_singleton_method(:add_encrypted_file_silently) { |content_path, key_path| file_calls << [content_path, key_path] }

    encrypted = @encrypted
    command.define_singleton_method(:encrypted_configuration) { encrypted }
    command.define_singleton_method(:encryption_key_file_generator) { key_generator }
    command.define_singleton_method(:encrypted_file_generator) { file_generator }

    @encrypted.key_value = true
    command.send(:ensure_encryption_key_has_been_added)
    assert_empty key_calls

    @encrypted.key_value = false
    command.send(:ensure_encryption_key_has_been_added)
    command.send(:ensure_encrypted_configuration_has_been_added)

    assert_equal ["config/master.key"], key_calls
    assert_equal [["config/credentials.yml.enc", "config/master.key"]], file_calls
  end

  test "change in system editor saves validates and reports invalid content warning" do
    command = command_for
    encrypted = @encrypted
    command.define_singleton_method(:encrypted_configuration) { encrypted }
    command.define_singleton_method(:using_system_editor) { |&block| block.call }
    command.define_singleton_method(:system_editor) { |tmp_path| "edited #{tmp_path}" }

    output = capture(:stdout) { command.send(:change_encrypted_configuration_in_system_editor) }

    assert_equal ["tmp/config.yml"], @encrypted.changed_paths
    assert_includes output, "File encrypted and saved."

    @encrypted.invalid_error = ActiveSupport::EncryptedConfiguration::InvalidContentError.new("Invalid YAML")
    output = capture(:stdout) { command.send(:change_encrypted_configuration_in_system_editor) }

    assert_includes output, "WARNING: Invalid YAML"
    assert_includes output, "Your application will not be able to load 'config/credentials.yml.enc'"
  end

  test "change reports missing key and invalid message errors" do
    command = command_for
    encrypted = @encrypted
    command.define_singleton_method(:encrypted_configuration) { encrypted }
    command.define_singleton_method(:using_system_editor) { |&block| block.call }
    command.define_singleton_method(:system_editor) { |_tmp_path| true }

    @encrypted.change_error = ActiveSupport::EncryptedFile::MissingKeyError.new(key_path: "config/master.key", env_key: "RAILS_MASTER_KEY")
    assert_includes capture(:stdout) { command.send(:change_encrypted_configuration_in_system_editor) }, "Missing encryption key"

    @encrypted.change_error = ActiveSupport::MessageEncryptor::InvalidMessage
    assert_includes capture(:stdout) { command.send(:change_encrypted_configuration_in_system_editor) }, "Couldn't decrypt config/credentials.yml.enc"
  end

  test "missing encrypted configuration message distinguishes key and file absence" do
    command = command_for
    encrypted = @encrypted
    command.define_singleton_method(:encrypted_configuration) { encrypted }

    @encrypted.key_value = false
    assert_includes command.send(:missing_encrypted_configuration_message), "Missing 'config/master.key'"

    @encrypted.key_value = true
    assert_includes command.send(:missing_encrypted_configuration_message), "File 'config/credentials.yml.enc' does not exist"
  end

  test "generator factories return rails generators" do
    command = command_for

    key_generator = command.send(:encryption_key_file_generator)
    file_generator = command.send(:encrypted_file_generator)

    assert_equal "Rails::Generators::EncryptionKeyFileGenerator", key_generator.class.name
    assert_equal "Rails::Generators::EncryptedFileGenerator", file_generator.class.name
  end

  private
    def command_for(args = ["config/credentials.yml.enc"], options = [])
      Rails::Command::EncryptedCommand.new(args, options)
    end

    def fake_encrypted(key:, read:)
      Struct.new(:key_value, :read_value, :requests, :changed_paths, :invalid_error, :change_error) do
        def key? = key_value
        def read = read_value
        def change
          raise change_error if change_error
          changed_paths << "tmp/config.yml"
          yield "tmp/config.yml"
        end
        def validate!
          raise invalid_error if invalid_error
        end
      end.new(key, read, [], [], nil, nil)
    end

    def with_rails_application(app)
      singleton = class << Rails; self; end
      original = Rails.method(:application)
      singleton.define_method(:application) { app }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.define_method(:application) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
