# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/command/base"
require "rails/commands/about/about_command"

class AboutCommandPublicContractTest < ActiveSupport::TestCase
  test "perform boots application and prints rails info" do
    command = Rails::Command::AboutCommand.new([], {}, {})
    events = []

    command.define_singleton_method(:boot_application!) do
      events << :boot_application
    end
    command.define_singleton_method(:say) do |message|
      events << [ :say, message ]
    end

    command.perform

    assert_equal :boot_application, events.first
    assert_equal [ :say, Rails::Info ], events.last
  end
end
