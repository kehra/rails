# frozen_string_literal: true

require_relative "../../../tools/component_simplecov"
require_relative "../../../tools/strict_warnings"
RailsComponentSimpleCov.start(component: "activemodel", track_paths: "activemodel/lib/**/*.rb")
require "active_model"

# Show backtraces for deprecated behavior for quicker cleanup.
ActiveModel.deprecator.behavior = :raise

# Disable available locale checks to avoid warnings running the test suite.
I18n.enforce_available_locales = false

require "active_support/testing/autorun"
require "active_support/testing/method_call_assertions"
require "active_support/core_ext/integer/time"

class ActiveModel::TestCase < ActiveSupport::TestCase
  include ActiveSupport::Testing::MethodCallAssertions
end

require_relative "../../../tools/test_common"
