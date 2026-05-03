# frozen_string_literal: true

require "abstract_unit"
require "rails/deprecator"

class RailsModuleTest < ActiveSupport::TestCase
  setup do
    @old_rails_env = Rails.env
    @old_rails_groups = ENV["RAILS_GROUPS"]
  end

  teardown do
    Rails.env = @old_rails_env
    if @old_rails_groups
      ENV["RAILS_GROUPS"] = @old_rails_groups
    else
      ENV.delete("RAILS_GROUPS")
    end
  end

  test "application accessors expose application state" do
    assert_same Rails.application, Rails.app
    assert_same Rails.application.config, Rails.configuration
    assert_same Rails.application.autoloaders, Rails.autoloaders
    assert_equal Rails.application.config.root, Rails.root
    assert_equal Pathname.new(Rails.application.paths["public"].first), Rails.public_path
  end

  test "backtrace cleaner error event reporters and deprecator are memoized global collaborators" do
    assert_instance_of Rails::BacktraceCleaner, Rails.backtrace_cleaner
    assert_same Rails.backtrace_cleaner, Rails.backtrace_cleaner
    assert_same ActiveSupport.error_reporter, Rails.error
    assert_same ActiveSupport.event_reporter, Rails.event
    assert_instance_of ActiveSupport::Deprecation, Rails.deprecator
    assert_same Rails.deprecator, Rails.deprecator
  end

  test "environment setter and groups include defaults env variables and dependency groups" do
    Rails.env = "development"
    ENV["RAILS_GROUPS"] = "assets,debug"

    assert_equal ActiveSupport::EnvironmentInquirer.new("development"), Rails.env
    assert_equal [ :default, "development", "assets", "debug", :console ], Rails.groups(console: [ :development ], ci: [ :test ])
  end

  test "root public path and autoloaders are nil safe when application is absent" do
    previous_application = Rails.application
    previous_app_class = Rails.app_class
    Rails.application = nil
    Rails.app_class = nil

    assert_nil Rails.application
    assert_nil Rails.root
    assert_nil Rails.public_path
  ensure
    Rails.app_class = previous_app_class
    Rails.application = previous_application
  end
end
