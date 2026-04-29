# frozen_string_literal: true

require "test_helper"
require "rails/generators/test_case"
require "rails/generators/channel/channel_generator"
require "rails/generators/test_unit/channel_generator"

class ChannelGeneratorTest < Rails::Generators::TestCase
  tests Rails::Generators::ChannelGenerator
  destination File.expand_path("../tmp/channel_generator", __dir__)

  setup :prepare_destination

  test "create_channel_files creates ruby channel without JavaScript assets" do
    run_generator [ "chat", "speak", "--no-assets", "--no-test-framework" ]

    assert_file "app/channels/application_cable/channel.rb", /class Channel < ActionCable::Channel::Base/
    assert_file "app/channels/application_cable/connection.rb", /class Connection < ActionCable::Connection::Base/
    assert_file "app/channels/chat_channel.rb", /class ChatChannel < ApplicationCable::Channel/, /def speak/
    assert_no_file "app/javascript/channels/chat_channel.js"
  end

  test "create_channel_files creates importmap JavaScript assets" do
    FileUtils.mkdir_p File.join(destination_root, "app/javascript")
    FileUtils.mkdir_p File.join(destination_root, "config")
    File.write File.join(destination_root, "app/javascript/application.js"), ""
    File.write File.join(destination_root, "config/importmap.rb"), ""

    run_generator [ "chat", "--assets", "--no-test-framework" ]

    assert_file "app/javascript/channels/index.js", /import "channels\/chat_channel"/
    assert_file "app/javascript/channels/consumer.js", /createConsumer/
    assert_file "app/javascript/channels/chat_channel.js", /import consumer from "channels\/consumer"/
    assert_file "app/javascript/application.js", /import "channels"/
    assert_file "config/importmap.rb", /pin "@rails\/actioncable"/, /pin_all_from "app\/javascript\/channels"/
  end

  test "create_channel_files appends JavaScript imports when setup already exists" do
    FileUtils.mkdir_p File.join(destination_root, "app/javascript/channels")
    File.write File.join(destination_root, "app/javascript/application.js"), ""
    File.write File.join(destination_root, "app/javascript/channels/index.js"), ""

    run_generator [ "chat", "--assets", "--no-test-framework" ]

    assert_no_file "app/javascript/channels/consumer.js"
    assert_file "app/javascript/channels/index.js", /import "\.\/chat_channel"/
    assert_file "app/javascript/channels/chat_channel.js", /import consumer from "\.\/consumer"/
  end

  test "create_channel_files installs JavaScript runtime dependencies in pretend mode" do
    FileUtils.mkdir_p File.join(destination_root, "app/javascript")
    File.write File.join(destination_root, "app/javascript/application.js"), ""
    File.write File.join(destination_root, "package.json"), "{}"

    output = run_generator [ "chat", "--assets", "--no-test-framework", "--pretend" ]

    assert_match(/Installing JavaScript dependencies/, output)
    assert_match(/yarn add @rails\/actioncable/, output)
  end

  test "create_channel_files without importmap or runtime skips dependency setup" do
    FileUtils.mkdir_p File.join(destination_root, "app/javascript")
    File.write File.join(destination_root, "app/javascript/application.js"), ""

    run_generator [ "chat", "--assets", "--no-test-framework" ]

    assert_file "app/javascript/channels/index.js", /import "\.\/chat_channel"/
    assert_file "app/javascript/channels/chat_channel.js", /import consumer from "\.\/consumer"/
  end

  test "create_channel_files skips shared channel files when revoking" do
    run_generator [ "chat", "--no-assets", "--no-test-framework" ], behavior: :revoke

    assert_no_file "app/channels/application_cable/channel.rb"
  end
end

class TestUnitChannelGeneratorTest < Rails::Generators::TestCase
  tests TestUnit::Generators::ChannelGenerator
  destination File.expand_path("../tmp/test_unit_channel_generator", __dir__)

  setup :prepare_destination

  test "create_test_files creates channel test" do
    run_generator [ "chat", "--skip-collision-check" ]

    assert_file "test/channels/chat_channel_test.rb", /class ChatChannelTest < ActionCable::Channel::TestCase/
  end

  test "create_test_files strips channel suffix" do
    run_generator [ "chat_channel", "--skip-collision-check" ]

    assert_file "test/channels/chat_channel_test.rb", /class ChatChannelTest < ActionCable::Channel::TestCase/
  end
end
