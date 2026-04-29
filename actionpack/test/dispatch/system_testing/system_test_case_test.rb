# frozen_string_literal: true

require "abstract_unit"
require "support/system_helper"
require "selenium/webdriver"

class SetDriverToRackTestTest < DrivenByRackTest
  test "uses rack_test" do
    assert_equal :rack_test, Capybara.current_driver
  end
end

class OverrideSeleniumSubclassToRackTestTest < DrivenBySeleniumWithChrome
  driven_by :rack_test

  test "uses rack_test" do
    assert_equal :rack_test, Capybara.current_driver
  end
end

class OverrideDriverWithExplicitName < DrivenBySeleniumWithChrome
  driven_by :selenium, options: { name: :best_driver }

  test "uses specified driver name" do
    assert_equal :best_driver, Capybara.current_driver
  end
end

class SetDriverToSeleniumTest < DrivenBySeleniumWithChrome
  test "uses selenium" do
    assert_equal :selenium, Capybara.current_driver
  end
end

class SetDriverToSeleniumHeadlessChromeTest < DrivenBySeleniumWithHeadlessChrome
  test "uses selenium headless chrome" do
    assert_equal :selenium, Capybara.current_driver
  end
end

class SetDriverToSeleniumHeadlessFirefoxTest < DrivenBySeleniumWithHeadlessFirefox
  test "uses selenium headless firefox" do
    assert_equal :selenium, Capybara.current_driver
  end
end

class DefaultsDriverAndServerTest < ActionDispatch::SystemTestCase
  test "uses default driver when subclass does not configure one" do
    assert_instance_of ActionDispatch::SystemTesting::Driver, self.class.driver
  end

  test "served_by configures capybara server" do
    old_host = Capybara.server_host
    old_port = Capybara.server_port

    self.class.served_by(host: "127.0.0.2", port: 3002)

    assert_equal "127.0.0.2", Capybara.server_host
    assert_equal 3002, Capybara.server_port
  ensure
    Capybara.server_host = old_host
    Capybara.server_port = old_port
  end
end
