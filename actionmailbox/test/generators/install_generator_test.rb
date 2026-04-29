# frozen_string_literal: true

require "test_helper"
require "generators/action_mailbox/install/install_generator"

class ActionMailboxInstallGeneratorTest < ActiveSupport::TestCase
  test "creates application mailbox file" do
    generator = ActionMailbox::Generators::InstallGenerator.new
    calls = []

    generator.stub(:say, ->(*args) { calls << [ :say, args ] }) do
      generator.stub(:template, ->(*args) { calls << [ :template, args ] }) do
        generator.create_action_mailbox_files
      end
    end

    assert_includes calls, [ :say, [ "Copying application_mailbox.rb to app/mailboxes", :green ] ]
    assert_includes calls, [ :template, [ "application_mailbox.rb", "app/mailboxes/application_mailbox.rb" ] ]
  end

  test "adds production ingress configuration" do
    generator = ActionMailbox::Generators::InstallGenerator.new
    calls = []

    generator.stub(:environment, ->(*args, **kwargs) { calls << [ args, kwargs ] }) do
      generator.add_action_mailbox_production_environment_config
    end

    assert_equal({ env: "production" }, calls.first.last)
    assert_includes calls.first.first.first, "config.action_mailbox.ingress = :relay"
  end

  test "installs active storage and action mailbox migrations" do
    generator = ActionMailbox::Generators::InstallGenerator.new
    calls = []

    generator.stub(:rails_command, ->(*args, **kwargs) { calls << [ args, kwargs ] }) do
      generator.create_migrations
    end

    assert_equal [ "railties:install:migrations FROM=active_storage,action_mailbox" ], calls.first.first
    assert_equal({ inline: true }, calls.first.last)
  end
end
