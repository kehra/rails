# frozen_string_literal: true

if ENV["COVERAGE"] == "1" || ENV["COVERAGE"] == "true"
  require "simplecov"

  component = File.basename(COMPONENT_ROOT)

  minimum_coverage =
    ENV.fetch("COVERAGE_MIN", nil) ||
    ENV.fetch("COVERAGE_MIN_#{component.upcase}", nil)

  minimum_coverage_by_file =
    ENV.fetch("COVERAGE_MIN_BY_FILE", nil) ||
    ENV.fetch("COVERAGE_MIN_BY_FILE_#{component.upcase}", nil)

  SimpleCov.start "rails" do
    enable_coverage :branch
    if minimum_coverage
      minimum_coverage minimum_coverage.to_f
    else
      minimum_coverage 75
    end

    if minimum_coverage_by_file
      minimum_coverage_by_file minimum_coverage_by_file.to_f
    else
      minimum_coverage_by_file 55
    end

    add_filter "/test/"
    add_filter "/tools/"
    command_name component
    coverage_dir File.join("coverage", component)
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
