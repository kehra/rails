# frozen_string_literal: true

if ENV["COVERAGE"] == "1" || ENV["COVERAGE"] == "true"
  require "simplecov"

  SimpleCov.start "rails" do
    enable_coverage :branch
    minimum_coverage 75
    minimum_coverage_by_file 55
    add_filter "/test/"
    add_filter "/tools/"
    command_name File.basename(COMPONENT_ROOT)
    coverage_dir File.join("coverage", File.basename(COMPONENT_ROOT))
  end
end

$: << File.expand_path("test", COMPONENT_ROOT)

require "bundler/setup"

require "rails/test_unit/runner"
require "rails/test_unit/reporter"
require "rails/test_unit/line_filtering"
require "active_support"
require "active_support/test_case"

ActiveSupport::TestCase.extend Rails::LineFiltering
Rails::TestUnitReporter.app_root ||= COMPONENT_ROOT
Rails::TestUnitReporter.executable = "bin/test"

Rails::TestUnit::Runner.parse_options(ARGV)
Rails::TestUnit::Runner.run(ARGV)
