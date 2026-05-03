# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/credentials/credentials_command"
require "active_support/encrypted_configuration"

class CredentialsPublicContractTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("rails-credentials-public-contract"))
    FileUtils.mkdir_p(@root.join("config/environments"))
    File.write(@root.join("config/environments/production.rb"), "")
    File.write(@root.join("config/environments/development.rb"), "")
    @credentials = fake_credentials(key: true, read: "foo:\n  bar: baz\n")
    @config = fake_credentials_config(@root.join("config/credentials.yml.enc"), @root.join("config/master.key"))
    @application = fake_application(@config, @credentials)
    @old_pwd = Dir.pwd
    Dir.chdir(@root)
  end

  teardown do
    Dir.chdir(@old_pwd)
    FileUtils.rm_rf(@root)
  end

  test "edit loads config switches conventional paths for specified environment and invokes editor flow" do
    command = command_for([], ["--environment=production"])
    calls = []
    command.define_singleton_method(:load_environment_config!) { calls << :load_environment_config }
    command.define_singleton_method(:load_generators) { calls << :load_generators }
    command.define_singleton_method(:ensure_encryption_key_has_been_added) { calls << :ensure_key }
    command.define_singleton_method(:ensure_credentials_have_been_added) { calls << :ensure_credentials }
    command.define_singleton_method(:ensure_diffing_driver_is_configured) { calls << :ensure_diffing }
    command.define_singleton_method(:change_credentials_in_system_editor) { calls << :change }

    with_rails_application(@application) { command.edit }

    assert_equal [ :load_environment_config, :load_generators, :ensure_key, :ensure_credentials, :ensure_diffing, :change ], calls
    assert_equal "config/credentials/production.yml.enc", command.send(:content_path)
    assert_equal "config/credentials/production.key", command.send(:key_path)
  end

  test "edit without explicit environment keeps configured paths" do
    command = command_for
    command.define_singleton_method(:load_environment_config!) {}
    command.define_singleton_method(:load_generators) {}
    command.define_singleton_method(:ensure_encryption_key_has_been_added) {}
    command.define_singleton_method(:ensure_credentials_have_been_added) {}
    command.define_singleton_method(:ensure_diffing_driver_is_configured) {}
    command.define_singleton_method(:change_credentials_in_system_editor) {}

    with_rails_application(@application) { command.edit }

    assert_equal "config/credentials.yml.enc", command.send(:content_path)
    assert_equal "config/master.key", command.send(:key_path)
  end

  test "edit honors overridden credential paths for specified environment" do
    @config.overridden_names = [ :content_path, :key_path ]
    command = command_for([], ["--environment=production"])
    command.define_singleton_method(:load_environment_config!) {}
    command.define_singleton_method(:load_generators) {}
    command.define_singleton_method(:ensure_encryption_key_has_been_added) {}
    command.define_singleton_method(:ensure_credentials_have_been_added) {}
    command.define_singleton_method(:ensure_diffing_driver_is_configured) {}
    command.define_singleton_method(:change_credentials_in_system_editor) {}

    with_rails_application(@application) { command.edit }

    assert_equal "config/credentials.yml.enc", command.send(:content_path)
    assert_equal "config/master.key", command.send(:key_path)
  end

  test "show prints decrypted content and missing credentials exits with contextual messages" do
    command = command_for
    command.define_singleton_method(:load_environment_config!) {}

    output = with_rails_application(@application) { capture(:stdout) { command.show } }
    assert_includes output, "foo:"

    @credentials.read_value = nil
    @credentials.key_value = false
    command = command_for
    command.define_singleton_method(:load_environment_config!) {}
    error_output = capture(:stderr) do
      assert_raises(SystemExit) { with_rails_application(@application) { command.show } }
    end
    assert_includes error_output, "Missing 'config/master.key'"

    @credentials.key_value = true
    error_output = capture(:stderr) do
      assert_raises(SystemExit) { with_rails_application(@application) { command.show } }
    end
    assert_includes error_output, "File 'config/credentials.yml.enc' does not exist"
  end

  test "diff decrypts explicit paths infers environments and falls back to encrypted content" do
    command = command_for
    command.define_singleton_method(:load_environment_config!) {}

    output = with_rails_application(@application) { capture(:stdout) { command.diff("config/credentials/production.yml.enc") } }
    assert_includes output, "foo:"
    assert_equal "production", command.send(:environment)

    command = command_for
    command.define_singleton_method(:load_environment_config!) {}
    @credentials.read_error = ActiveSupport::MessageEncryptor::InvalidMessage
    @credentials.content_path = Struct.new(:read).new("encrypted-content")

    output = with_rails_application(@application) { capture(:stdout) { command.diff("config/credentials/custom.yml.enc") } }
    assert_includes output, "encrypted-content"
    assert_equal "custom", command.send(:environment)
  end

  test "diff without path does nothing when no enroll options are set" do
    command = command_for
    calls = []
    command.define_singleton_method(:disenroll_project_from_credentials_diffing) { calls << :disenroll }
    command.define_singleton_method(:enroll_project_in_credentials_diffing) { calls << :enroll }

    command.diff

    assert_empty calls
  end

  test "diff without path delegates enroll and disenroll options" do
    command = command_for
    calls = []
    command.options = command.options.merge(enroll: true, disenroll: true)
    command.define_singleton_method(:disenroll_project_from_credentials_diffing) { calls << :disenroll }
    command.define_singleton_method(:enroll_project_in_credentials_diffing) { calls << :enroll }

    command.diff

    assert_equal [ :disenroll, :enroll ], calls
  end

  test "fetch prints nested credential values and exits for missing paths or files" do
    command = command_for
    command.define_singleton_method(:load_environment_config!) {}
    output = with_rails_application(@application) { capture(:stdout) { command.fetch("foo.bar") } }
    assert_equal "baz\n", output

    error_output = capture(:stderr) do
      assert_raises(SystemExit) { with_rails_application(@application) { command.fetch("foo.missing") } }
    end
    assert_includes error_output, "Invalid or missing credential path: foo.missing"

    @credentials.read_value = nil
    error_output = capture(:stderr) do
      assert_raises(SystemExit) { with_rails_application(@application) { command.fetch("foo.bar") } }
    end
    assert_includes error_output, "File 'config/credentials.yml.enc' does not exist"
  end

  test "ensure key and credentials generation delegate to generators with environment secret key rules" do
    command = command_for([], ["--environment=development"])
    key_calls = []
    credentials_calls = []
    require "rails/generators"
    require "rails/generators/rails/encryption_key_file/encryption_key_file_generator"
    require "rails/generators/rails/credentials/credentials_generator"
    encrypted = @credentials
    command.define_singleton_method(:credentials) { encrypted }
    original_add_key_file = Rails::Generators::EncryptionKeyFileGenerator.instance_method(:add_key_file)
    original_credentials_initialize = Rails::Generators::CredentialsGenerator.instance_method(:initialize)
    original_invoke_all = Rails::Generators::CredentialsGenerator.instance_method(:invoke_all)
    Rails::Generators::EncryptionKeyFileGenerator.define_method(:add_key_file) { |path| key_calls << path }
    Rails::Generators::CredentialsGenerator.define_method(:initialize) { |args, options = {}, *| credentials_calls << [args, options] }
    Rails::Generators::CredentialsGenerator.define_method(:invoke_all) { credentials_calls << :invoke_all }
    command.instance_variable_set(:@content_path, "config/credentials/development.yml.enc")
    command.instance_variable_set(:@key_path, "config/credentials/development.key")

    begin
      with_rails_application(@application) do
        @credentials.key_value = true
        command.send(:ensure_encryption_key_has_been_added)
        @credentials.key_value = false
        command.send(:ensure_encryption_key_has_been_added)
        command.send(:ensure_credentials_have_been_added)
      end
    ensure
      Rails::Generators::EncryptionKeyFileGenerator.define_method(:add_key_file, original_add_key_file)
      Rails::Generators::CredentialsGenerator.define_method(:initialize, original_credentials_initialize)
      Rails::Generators::CredentialsGenerator.define_method(:invoke_all, original_invoke_all)
    end

    assert_equal [ "config/credentials/development.key" ], key_calls
    assert_equal [[ ["config/credentials/development.yml.enc", "config/credentials/development.key"], { skip_secret_key_base: true, quiet: true } ], :invoke_all], credentials_calls
  end

  test "change in editor reports save validation warnings and decrypt errors" do
    command = command_for
    command.define_singleton_method(:using_system_editor) { |&block| block.call }
    command.define_singleton_method(:system_editor) { |tmp_path| "edited #{tmp_path}" }

    output = with_rails_application(@application) { capture(:stdout) { command.send(:change_credentials_in_system_editor) } }
    assert_includes output, "Editing config/credentials.yml.enc"
    assert_includes output, "File encrypted and saved."
    assert_equal ["tmp/credentials.yml"], @credentials.changed_paths

    @credentials.invalid_error = ActiveSupport::EncryptedConfiguration::InvalidContentError.new("Invalid YAML")
    output = with_rails_application(@application) { capture(:stdout) { command.send(:warn_if_credentials_are_invalid) } }
    assert_includes output, "WARNING: Invalid YAML"
    assert_includes output, "Your application will not be able to load 'config/credentials.yml.enc'"

    @credentials.change_error = ActiveSupport::EncryptedFile::MissingKeyError.new(key_path: "config/master.key", env_key: "RAILS_MASTER_KEY")
    assert_includes with_rails_application(@application) { capture(:stdout) { command.send(:change_credentials_in_system_editor) } }, "Missing encryption key"

    @credentials.change_error = ActiveSupport::MessageEncryptor::InvalidMessage
    assert_includes with_rails_application(@application) { capture(:stdout) { command.send(:change_credentials_in_system_editor) } }, "Couldn't decrypt config/credentials.yml.enc"
  end

  private
    def command_for(args = [], options = [])
      Rails::Command::CredentialsCommand.new(args, options)
    end

    def fake_credentials_config(content_path, key_path)
      Struct.new(:content_path, :key_path, :overridden_names) do
        def overridden?(name) = overridden_names.include?(name)
      end.new(content_path, key_path, [])
    end

    def fake_application(config, credentials)
      app_config = Struct.new(:credentials).new(config)
      Struct.new(:config, :credentials) do
        def encrypted(content_path, key_path:)
          credentials.requests << [content_path, key_path]
          credentials
        end
      end.new(app_config, credentials)
    end

    def fake_credentials(key:, read:)
      Struct.new(:key_value, :read_value, :requests, :changed_paths, :invalid_error, :change_error, :read_error, :content_path) do
        def key? = key_value
        def read
          raise read_error if read_error
          read_value
        end
        def change
          raise change_error if change_error
          changed_paths << "tmp/credentials.yml"
          yield "tmp/credentials.yml"
        end
        def validate!
          raise invalid_error if invalid_error
        end
      end.new(key, read, [], [], nil, nil, nil, Struct.new(:read).new("encrypted"))
    end

    def with_rails_application(app)
      singleton = class << Rails; self; end
      original_application = Rails.method(:application)
      original_root = Rails.method(:root)
      root = @root
      singleton.define_method(:application) { app }
      singleton.define_method(:root) { root }
      yield
    ensure
      singleton.send(:remove_method, :application) if singleton.method_defined?(:application)
      singleton.send(:remove_method, :root) if singleton.method_defined?(:root)
      singleton.define_method(:application) { |*args, **kwargs, &block| original_application.call(*args, **kwargs, &block) }
      singleton.define_method(:root) { |*args, **kwargs, &block| original_root.call(*args, **kwargs, &block) }
    end
end
