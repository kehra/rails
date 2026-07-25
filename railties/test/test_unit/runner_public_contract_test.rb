# frozen_string_literal: true

require "abstract_unit"
require "optparse"
require "rails/test_unit/runner"

class RailsTestUnitRunnerPublicContractTest < ActiveSupport::TestCase
  setup do
    @old_rails_env = ENV["RAILS_ENV"]
    @old_default_test = ENV["DEFAULT_TEST"]
    @old_default_test_exclude = ENV["DEFAULT_TEST_EXCLUDE"]
    @old_testopts = ENV["TESTOPTS"]
    @old_verbose = $VERBOSE
    Rails::TestUnit::Runner.filters.clear
  end

  teardown do
    ENV["RAILS_ENV"] = @old_rails_env
    ENV["DEFAULT_TEST"] = @old_default_test
    ENV["DEFAULT_TEST_EXCLUDE"] = @old_default_test_exclude
    ENV["TESTOPTS"] = @old_testopts
    $VERBOSE = @old_verbose
    Rails::TestUnit::Runner.filters.clear
  end

  test "invalid test error formats message and suppresses backtrace" do
    error = Rails::TestUnit::InvalidTestError.new("test/models/accnt.rb", "Did you mean? account_test.rb")

    assert_equal "Could not load test file: test/models/accnt.rb.\nDid you mean? account_test.rb", error.message
    assert_equal [], error.backtrace
  end

  test "attach before load options accepts environment and warnings flags" do
    opts = OptionParser.new
    Rails::TestUnit::Runner.attach_before_load_options(opts)

    assert_nothing_raised { opts.parse(["--warnings", "--environment", "production"]) }
    assert_nothing_raised { opts.parse(["-w", "-e", "development"]) }
  end

  test "parse options extracts environment and warnings" do
    argv = ["--environment", "development", "--warnings", "test/models/account_test.rb"]

    Rails::TestUnit::Runner.parse_options(argv)

    assert_equal "development", ENV["RAILS_ENV"]
    assert_equal ["test/models/account_test.rb"], argv
    assert_equal true, $VERBOSE

    argv = ["-e", "production", "-w"]
    Rails::TestUnit::Runner.parse_options(argv)
    assert_equal "production", ENV["RAILS_ENV"]
    assert_empty argv

    ENV["RAILS_ENV"] = nil
    Rails::TestUnit::Runner.parse_options([])
    assert_equal "test", ENV["RAILS_ENV"]
  end

  test "run enables deferred test loading and installs argv replacement" do
    Rails::TestUnit::Runner.run(["test/models/account_test.rb"])

    assert_equal true, Rails::TestUnit::Runner.load_test_files
  end

  test "run from rake invokes rails command with testopts and exits on failure" do
    calls = []
    with_runner_singleton(:system, ->(*args) { calls << [:system, args]; true }) do
      Rails::TestUnit::Runner.run_from_rake("test", ["test/models/account_test.rb"])
    end
    assert_equal [[:system, ["rails", "test", "test/models/account_test.rb"]]], calls

    ENV["TESTOPTS"] = "--seed 123 --name test_contract"
    with_runner_singleton(:system, ->(*args) { calls << [:system_failure, args]; false }) do
      with_runner_singleton(:exit, ->(status) { calls << [:exit, status]; :exited }) do
        Rails::TestUnit::Runner.run_from_rake("test:models", [])
      end
    end

    assert_includes calls, [:system_failure, ["rails", "test:models", "--seed", "123", "--name", "test_contract"]]
    assert_includes calls, [:exit, false]
  end

  test "load tests extracts filters expands directories excludes defaults and suggests corrections" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p("test/models")
        FileUtils.mkdir_p("test/system")
        File.write("test/models/account_test.rb", "$runner_loaded ||= []; $runner_loaded << :account\n")
        File.write("test/system/system_test.rb", "raise 'excluded default should not load'\n")

        Rails::TestUnit::Runner.load_tests([])
        assert_equal [:account], $runner_loaded

        error = assert_raises(Rails::TestUnit::InvalidTestError) do
          Rails::TestUnit::Runner.load_tests(["test/models/accnt_test.rb"])
        end
        assert_match(/Could not load test file: test\/models\/accnt_test\.rb\./, error.message)
        assert_match(/account_test\.rb/, error.message)
      ensure
        $runner_loaded = nil
      end
    end
  end

  test "load tests reraises missing files without suggestions and nested load errors" do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        assert_raises(LoadError) { Rails::TestUnit::Runner.load_tests(["missing_test.rb"]) }

        File.write("nested_test.rb", "raise LoadError, 'nested dependency missing'\n")
        error = assert_raises(LoadError) { Rails::TestUnit::Runner.load_tests(["nested_test.rb"]) }
        assert_equal "nested dependency missing", error.message
      end
    end
  end

  test "load tests records path directory and line filters" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "test/models"))
      path = File.join(dir, "test/models/account_test.rb")
      File.write(path, "$runner_filter_loaded = true\n")

      Rails::TestUnit::Runner.load_tests([File.join(dir, "test/models"), "#{path}:3-5:9"])

      assert $runner_filter_loaded
      assert_includes Rails::TestUnit::Runner.filters, [path, ["3-5", "9"]]
    ensure
      $runner_filter_loaded = nil
    end
  end

  test "compose filter normalizes names regexps existing named filters and line filters" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "sample_test.rb")
      line = 20
      source = "\n" * (line - 1) + "def test_sample_contract; assert true; end\n"
      File.write(file, source)
      runnable = Class.new
      runnable.class_eval(source, file, 1)

      Rails::TestUnit::Runner.filters << [nil, []]
      Rails::TestUnit::Runner.filters << [file, []]
      Rails::TestUnit::Runner.filters << [file, [line.to_s]]
      filter = Rails::TestUnit::Runner.compose_filter(runnable, "sample contract")
      assert_equal "test_sample_contract", filter.named_filter
      assert filter === :test_sample_contract
      refute filter === :test_other_contract

      filter = Rails::TestUnit::Runner.compose_filter(runnable, "/other contract/")
      assert_instance_of Regexp, filter.named_filter
      assert filter === :test_sample_contract

      named = Struct.new(:named_filter) do
        def ===(_method) = false
      end.new("custom_name")
      filter = Rails::TestUnit::Runner.compose_filter(runnable, named)
      assert_equal "custom_name", filter.named_filter

      unnamed = Class.new do
        def =~(_other) = nil
      end.new
      filter = Rails::TestUnit::Runner.compose_filter(runnable, unnamed)
      assert_nil filter.named_filter
    end
  end

  test "compose filter returns normalized filter when there are no line filters" do
    assert_equal "test_sample_contract", Rails::TestUnit::Runner.compose_filter(Class.new, "sample contract")
    assert_equal "test_sample_contract", Rails::TestUnit::Runner.compose_filter(Class.new, "test_sample_contract")
    assert_match Rails::TestUnit::Runner.compose_filter(Class.new, "/sample contract/"), "/sample_contract|sample contract/"
  end

  test "line filter matches methods whose definitions overlap selected lines" do
    Dir.mktmpdir do |dir|
      file = File.join(dir, "line_sample_test.rb")
      line = 12
      source = "\n" * (line - 1) + "def test_line_contract; assert true; end\n"
      File.write(file, source)
      runnable = Class.new
      runnable.class_eval(source, file, 1)

      filter = Rails::TestUnit::Filter.new(runnable, file, line.to_s)
      assert filter === :test_line_contract
      refute filter === :test_missing_contract
    end
  end

  private
    def with_runner_singleton(method_name, implementation)
      singleton = class << Rails::TestUnit::Runner; self; end
      had_method = singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
      original = Rails::TestUnit::Runner.method(method_name) if Rails::TestUnit::Runner.respond_to?(method_name, true)
      singleton.define_method(method_name, &implementation)
      yield
    ensure
      singleton.remove_method(method_name) if singleton.method_defined?(method_name) || singleton.private_method_defined?(method_name)
      singleton.define_method(method_name) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) } if had_method && original
    end
end
