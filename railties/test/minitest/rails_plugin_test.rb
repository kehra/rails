# frozen_string_literal: true

require "abstract_unit"

class Minitest::RailsPluginTest < ActiveSupport::TestCase
  FakeProfileResult = Struct.new(:time, :location, :source_location) do
    def to_json(*)
      { time: time, name: location }.to_json
    end
  end

  setup do
    @output = StringIO.new("".encode("UTF-8"))
  end

  test "replaces backtrace filter with one that silences gem lines" do
    backtrace = ["lib/my_code.rb", backtrace_gem_line("rails")]

    with_plugin do
      assert_equal backtrace.take(1), Minitest.backtrace_filter.filter(backtrace)
    end
  end

  test "replacement backtrace filter never returns an empty backtrace" do
    backtrace = [backtrace_gem_line("rails")]

    with_plugin do
      assert_equal backtrace, Minitest.backtrace_filter.filter(backtrace)
    end
  end

  test "replacement backtrace filter silences Minitest lines when all lines are gem lines" do
    backtrace = [backtrace_gem_line("rails"), backtrace_gem_line("minitest")]

    with_plugin do
      assert_equal backtrace.take(1), Minitest.backtrace_filter.filter(backtrace)
    end
  end

  test "does not replace backtrace filter when using --backtrace option" do
    backtrace_filter = baseline_backtrace_filter

    with_plugin("--backtrace", initial_backtrace_filter: backtrace_filter) do
      assert_same backtrace_filter, Minitest.backtrace_filter
    end

    with_plugin("-b", initial_backtrace_filter: backtrace_filter) do
      assert_same backtrace_filter, Minitest.backtrace_filter
    end
  end

  test "replaces Minitest::SummaryReporter reporter" do
    with_plugin do
      assert_empty Minitest.reporter.reporters.select { |reporter| reporter.instance_of? Minitest::SummaryReporter }
      assert_not_empty Minitest.reporter.reporters.grep(Minitest::SuppressedSummaryReporter)
    end
  end

  test "replaces Minitest::ProgressReporter reporter" do
    with_plugin do
      assert_empty Minitest.reporter.reporters.grep(Minitest::ProgressReporter)
      assert_not_empty Minitest.reporter.reporters.grep(::Rails::TestUnitReporter)
    end
  end

  test "keeps non-default reporters" do
    custom_reporter = Minitest::Reporter.new(@output)

    with_plugin(initial_reporters: [custom_reporter]) do
      assert_includes Minitest.reporter.reporters, custom_reporter
    end
  end

  test "does not add reporters when not replacing reporters" do
    with_plugin(initial_reporters: []) do
      assert_empty Minitest.reporter.reporters
    end
  end

  test "adds profile reporter when profile option is enabled" do
    with_plugin("--profile") do
      reporter = Minitest.reporter.reporters.grep(Minitest::ProfileReporter).first
      assert_instance_of Minitest::ProfileReporter, reporter
    end
  end

  test "does nothing unless rails test environment is enabled" do
    original_reporter = Minitest::CompositeReporter.new(*baseline_reporters)
    original_backtrace_filter = baseline_backtrace_filter

    with_env("RAILS_ENV" => nil, "RAILS_MINITEST_PLUGIN" => nil) do
      original_global_reporter, Minitest.reporter = Minitest.reporter, original_reporter
      original_global_filter, Minitest.backtrace_filter = Minitest.backtrace_filter, original_backtrace_filter
      Minitest.plugin_rails_init(io: @output)
      assert_same original_reporter, Minitest.reporter
      assert_same original_backtrace_filter, Minitest.backtrace_filter
    ensure
      Minitest.reporter = original_global_reporter
      Minitest.backtrace_filter = original_global_filter
    end
  end

  test "skips backtrace replacement when rails backtrace cleaner is unavailable" do
    backtrace_filter = baseline_backtrace_filter
    singleton = class << ::Rails; self; end
    original = ::Rails.method(:respond_to?)
    singleton.define_method(:respond_to?) do |name, include_private = false|
      name == :backtrace_cleaner ? false : original.call(name, include_private)
    end

    with_plugin(initial_backtrace_filter: backtrace_filter) do
      assert_same backtrace_filter, Minitest.backtrace_filter
    end
  ensure
    singleton.define_method(:respond_to?) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
  end

  test "rails options parse flags positional files and profile counts" do
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, "app_test.rb")
      File.write(test_file, "# loaded by plugin option test\n")

      warning = capture_io do
        options = Minitest.process_args(["--defer-output", "--fail-fast", "--no-color", test_file])
        assert_equal false, options[:output_inline]
        assert_equal true, options[:fail_fast]
        assert_equal false, options[:color]
        assert_equal [test_file], options[:test_files]
      end.last
      assert_empty warning
    end

    options = Minitest.process_args(["--profile"])
    assert_equal 10, options[:profile]

    options = Minitest.process_args(["--profile", "3"])
    assert_equal 3, options[:profile]

    warning = capture_io do
      options = Minitest.process_args(["--profile", "not-a-count"])
      assert_equal 10, options[:profile]
    end.last
    assert_match(/Non integer specified as profile count/, warning)
  end

  test "legacy name option maps to include with a warning" do
    warning = capture_io do
      options = Minitest.process_args(["--name", "/contract/"])
      assert_equal "/contract/", options[:include]
    end.last

    assert_match(/Please switch from -n\/--name to -i\/--include/, warning)
  end

  test "does not install legacy name option for old minitest versions" do
    with_constant(Minitest, :VERSION, "5.0.0") do
      options = {}
      opts = OptionParser.new
      Minitest.plugin_rails_options(opts, options)
      refute_match(/--name/, opts.to_s)
    end
  end

  test "load hook honors disabled test file loading" do
    singleton = class << ::Rails::TestUnit::Runner; self; end
    original = ::Rails::TestUnit::Runner.method(:load_test_files)
    singleton.define_method(:load_test_files) { false }

    assert_nothing_raised { Minitest.process_args([File.join(Dir.mktmpdir, "missing_test.rb")]) }
  ensure
    singleton.define_method(:load_test_files) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
  end

  test "suppressed summary reporter only aggregates when output is deferred" do
    inline_reporter = Minitest::SuppressedSummaryReporter.new(@output, output_inline: true)
    deferred_reporter = Minitest::SuppressedSummaryReporter.new(@output, output_inline: false)

    assert_nil inline_reporter.aggregated_results(StringIO.new)
    assert_same deferred_output = StringIO.new, deferred_reporter.aggregated_results(deferred_output)
  end

  test "profile reporter records results prints summaries and writes output files" do
    result = FakeProfileResult.new(0.2, "SlowTest#test_contract", [File.join(Dir.pwd, "test/slow_test.rb"), 12])
    faster = FakeProfileResult.new(0.1, "FastTest#test_contract", ["/external/fast_test.rb", 3])
    no_source = FakeProfileResult.new(0.0, "NoSourceTest#test_contract", [nil, nil])
    reporter = Minitest::ProfileReporter.new(@output, profile: 3)

    reporter.record(faster)
    reporter.record(result)
    reporter.record(no_source)

    assert reporter.passed?
    reporter.report
    reporter.summary

    output = @output.string
    assert_match(/Top 3 slowest tests \(0\.30 seconds, 100\.0% of total time\)/, output)
    assert_match(/SlowTest#test_contract/, output)
    assert_match(%r{test/slow_test.rb:12}, output)
    assert_match(/FastTest#test_contract/, output)
    assert_match(%r{/external/fast_test.rb:3}, output)
    assert_match(/NoSourceTest#test_contract/, output)

    empty_reporter = Minitest::ProfileReporter.new(@output, profile: 10)
    empty_reporter.summary
    assert_match(/Top 0 slowest tests \(0\.00 seconds, 0\.0% of total time\)/, @output.string)

    Dir.mktmpdir do |dir|
      output_file = File.join(dir, "results.jsonl")
      with_env("RAILTIES_OUTPUT_FILE" => output_file) do
        file_reporter = Minitest::ProfileReporter.new(StringIO.new, profile: 10)
        file_reporter.record(result)
        assert_empty file_reporter.results
        assert_nil file_reporter.report
      end

      line = File.read(output_file)
      assert_match(/SlowTest#test_contract/, line)
      assert_match(/location/, line)
    end
  end

  private
    def baseline_backtrace_filter
      Minitest::BacktraceFilter.new
    end

    def baseline_reporters
      [Minitest::SummaryReporter.new(@output), Minitest::ProgressReporter.new(@output)]
    end

    def with_plugin(*args, initial_backtrace_filter: baseline_backtrace_filter, initial_reporters: baseline_reporters)
      original_backtrace_filter, Minitest.backtrace_filter = Minitest.backtrace_filter, initial_backtrace_filter
      original_reporter, Minitest.reporter = Minitest.reporter, Minitest::CompositeReporter.new(*initial_reporters)

      options = Minitest.process_args(args)
      Minitest.plugin_rails_init(options)

      yield
    ensure
      Minitest.backtrace_filter = original_backtrace_filter
      Minitest.reporter = original_reporter
    end

    def with_env(values)
      old_values = values.keys.to_h { |key| [key, ENV[key]] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      values.each_key { |key| ENV[key] = old_values[key] }
    end

    def with_constant(mod, name, value)
      original = mod.const_get(name)
      mod.send(:remove_const, name)
      mod.const_set(name, value)
      yield
    ensure
      mod.send(:remove_const, name)
      mod.const_set(name, original)
    end

    def backtrace_gem_line(gem_name)
      caller.grep(%r"/lib/minitest\.rb:").first.gsub("minitest", gem_name)
    end
end
