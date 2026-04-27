# frozen_string_literal: true

module RailsComponentSimpleCov
  module_function

  class QuietFormatter
    def format(result)
      original_stdout = $stdout
      File.open(File::NULL, "w") do |null|
        $stdout = null
        SimpleCov::Formatter::HTMLFormatter.new.format(result)
      end
    ensure
      $stdout = original_stdout
    end
  end

  DEFAULT_TRACK_PATHS = {
    "actioncable" => "actioncable/lib/**/*.rb",
    "actionmailbox" => ["actionmailbox/app/**/*.rb", "actionmailbox/lib/**/*.rb"],
    "actionmailer" => "actionmailer/lib/**/*.rb",
    "actionpack" => "actionpack/lib/**/*.rb",
    "actiontext" => ["actiontext/app/**/*.rb", "actiontext/lib/**/*.rb"],
    "actionview" => "actionview/lib/**/*.rb",
    "activejob" => "activejob/lib/**/*.rb",
    "activemodel" => "activemodel/lib/**/*.rb",
    "activerecord" => "activerecord/lib/**/*.rb",
    "activestorage" => ["activestorage/app/**/*.rb", "activestorage/lib/**/*.rb"],
    "activesupport" => "activesupport/lib/**/*.rb",
    "railties" => "railties/lib/**/*.rb",
  }.freeze

  def start(component:, track_paths:)
    return unless ENV["SIMPLECOV"]
    return if defined?(@started) && @started

    require "simplecov"

    repo_root = File.expand_path("..", __dir__)
    coverage_dir = ENV["SIMPLECOV_COVERAGE_DIR"] || File.join(repo_root, "coverage", component)
    root_pid = Process.pid

    SimpleCov.root(repo_root)
    SimpleCov.command_name(ENV.fetch("SIMPLECOV_COMMAND_NAME", component))
    SimpleCov.coverage_dir(coverage_dir)
    SimpleCov.formatter = QuietFormatter
    SimpleCov.at_exit do
      SimpleCov.result.format! if Process.pid == root_pid
    end
    SimpleCov.start do
      enable_coverage :branch
      primary_coverage :branch
      Array(track_paths).each do |track_path|
        track_files(track_path)
      end
      add_filter "/test/"
    end

    @started = true
  end

  def auto_start_from_env
    component = ENV["SIMPLECOV_COMPONENT"]
    return unless component

    track_paths = ENV["SIMPLECOV_TRACK_PATHS"]&.split(File::PATH_SEPARATOR) || DEFAULT_TRACK_PATHS.fetch(component)
    start(component: component, track_paths: track_paths)
    remove_coverage_env
  end

  def remove_coverage_env
    remove_coverage_env_from(ENV)
    remove_coverage_env_from(Bundler.const_get(:ORIGINAL_ENV)) if defined?(Bundler::ORIGINAL_ENV)
  end

  def remove_coverage_env_from(env)
    rubyopt = env["RUBYOPT"].to_s.split.reject do |option|
      coverage_rubyopt_options.include?(option)
    end

    if rubyopt.empty?
      env.delete("RUBYOPT")
    else
      env["RUBYOPT"] = rubyopt.join(" ")
    end

    env.delete("SIMPLECOV")
    env.delete("SIMPLECOV_COMPONENT")
    env.delete("SIMPLECOV_TRACK_PATHS")
  end

  def coverage_rubyopt_options
    component_loader = "-r#{File.expand_path(__FILE__)}"
    [
      "-rbundler/setup",
      component_loader,
      component_loader.delete_suffix(".rb"),
    ]
  end
end

RailsComponentSimpleCov.auto_start_from_env
