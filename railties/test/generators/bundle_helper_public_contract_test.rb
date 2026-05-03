# frozen_string_literal: true

require "abstract_unit"
require "minitest/mock"
require "rails/generators/bundle_helper"

class BundleHelperPublicContractTest < ActiveSupport::TestCase
  class Generator
    include Rails::Generators::BundleHelper

    attr_reader :statuses, :system_calls, :options

    def initialize(options = {})
      @options = options
      @statuses = []
      @system_calls = []
    end

    def say_status(status, message)
      statuses << [status, message]
    end

    def system(*args)
      system_calls << args
      true
    end

    def exec(command, env = {}, params = {})
      bundle_command(command, env, params)
    end
  end

  test "bundle command reports status and executes through bundler original env" do
    generator = Generator.new
    yielded = false

    Gem.stub(:bin_path, "/path/to/bundle") do
      Bundler.stub(:with_original_env, ->(&block) { yielded = true; block.call }) do
        generator.exec("install", { "BUNDLE_IGNORE_MESSAGES" => "1" })
      end
    end

    assert yielded
    assert_equal [[:run, "bundle install"]], generator.statuses
    assert_equal [[{ "BUNDLE_IGNORE_MESSAGES" => "1" }, %Q["#{Gem.ruby}" "/path/to/bundle" install]]], generator.system_calls
  end

  test "bundle command redirects output when generator or params request quiet" do
    quiet_generator = Generator.new(quiet: true)
    params_generator = Generator.new

    Gem.stub(:bin_path, "/path/to/bundle") do
      Bundler.stub(:with_original_env, ->(&block) { block.call }) do
        quiet_generator.exec("install")
        params_generator.exec("add debug", {}, quiet: true)
      end
    end

    assert_equal [[{}, %Q["#{Gem.ruby}" "/path/to/bundle" install], { out: File::NULL }]], quiet_generator.system_calls
    assert_equal [[{}, %Q["#{Gem.ruby}" "/path/to/bundle" add debug], { out: File::NULL }]], params_generator.system_calls
  end
end
