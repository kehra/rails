# frozen_string_literal: true

require "test_helper"

ENV["RACK_ENV"] ||= "test"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome do |options|
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
  end
end

Capybara.server = :puma, { Silent: true }
