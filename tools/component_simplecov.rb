# frozen_string_literal: true

module RailsComponentSimpleCov
  module_function

  def start(component:, track_paths:)
    return unless ENV["SIMPLECOV"]
    return if defined?(@started) && @started

    require "simplecov"

    repo_root = File.expand_path("..", __dir__)
    coverage_dir = ENV["SIMPLECOV_COVERAGE_DIR"] || File.join(repo_root, "coverage", component)

    SimpleCov.root(repo_root)
    SimpleCov.command_name(ENV.fetch("SIMPLECOV_COMMAND_NAME", component))
    SimpleCov.coverage_dir(coverage_dir)
    SimpleCov.start do
      enable_coverage :branch
      Array(track_paths).each do |track_path|
        track_files(track_path)
      end
      add_filter "/test/"
    end

    @started = true
  end
end
