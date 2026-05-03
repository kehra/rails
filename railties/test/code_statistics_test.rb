# frozen_string_literal: true

require "abstract_unit"
require "rails/code_statistics"

class CodeStatisticsTest < ActiveSupport::TestCase
  def setup
    @tmp_path = File.expand_path("fixtures/tmp", __dir__)
    @dir_js   = File.join(@tmp_path, "lib.js")
    FileUtils.mkdir_p(@dir_js)
  end

  def teardown
    FileUtils.rm_rf(@tmp_path)
  end

  test "register directories" do
    Rails::CodeStatistics.register_directory("My Directory", "path/to/dir")
    assert Rails::CodeStatistics.directories.include?(["My Directory", "path/to/dir"])
    assert_not Rails::CodeStatistics.test_types.include?("My Directory")
  ensure
    Rails::CodeStatistics.directories.delete(["My Directory", "path/to/dir"])
  end

  test "register test directories" do
    Rails::CodeStatistics.register_directory("Model specs", "spec/models", test_directory: true)
    assert Rails::CodeStatistics.test_types.include?("Model specs")
  ensure
    Rails::CodeStatistics.test_types.delete("Model specs")
  end

  test "register test extensions" do
    Rails::CodeStatistics.register_extension("slim")
    assert Rails::CodeStatistics.pattern.to_s.include?("slim")
  ensure
    Rails::CodeStatistics.extensions = Rails::CodeStatistics::EXTENSIONS
    Rails::CodeStatistics.pattern = Rails::CodeStatistics::PATTERN
  end

  test "ignores directories that happen to have source files extensions" do
    assert_nothing_raised do
      @code_statistics = Rails::CodeStatistics.new(["tmp dir", @tmp_path])
    end
  end

  test "ignores hidden files" do
    File.write File.join(@tmp_path, ".example.rb"), <<-CODE
      def foo
        puts 'foo'
      end
    CODE

    assert_nothing_raised do
      Rails::CodeStatistics.new(["hidden file", @tmp_path])
    end
  end

  test "prints statistics with totals and code to test ratio" do
    app_dir = File.join(@tmp_path, "app")
    test_dir = File.join(@tmp_path, "test")
    FileUtils.mkdir_p([app_dir, test_dir])
    File.write File.join(app_dir, "model.rb"), <<~RUBY
      class Model
        def call
          true
        end
      end
    RUBY
    File.write File.join(test_dir, "model_test.rb"), <<~RUBY
      class ModelTest
        test "call" do
          assert true
        end
      end
    RUBY

    stats = Rails::CodeStatistics.new(["Models", app_dir], ["Model tests", test_dir])
    output = capture(:stdout) { assert_nil stats.to_s }

    assert_match(/\| Models\s+\|\s+5 \|\s+5 \|\s+1 \|\s+1 \|\s+1 \|\s+3 \|/, output)
    assert_match(/\| Model tests\s+\|\s+5 \|\s+5 \|\s+1 \|\s+1 \|\s+1 \|\s+3 \|/, output)
    assert_match(/\| Total\s+\|\s+10 \|\s+10 \|\s+2 \|\s+2 \|\s+1 \|\s+3 \|/, output)
    assert_match(/Code LOC: 5\s+Test LOC: 5\s+Code to Test Ratio: 1:1\.0/, output)
  end

  test "prints statistics without total for a single directory and handles zero divisors" do
    empty_dir = File.join(@tmp_path, "empty")
    FileUtils.mkdir_p(empty_dir)
    File.write File.join(empty_dir, "README.txt"), "not counted\n"

    stats = Rails::CodeStatistics.new(["Empty", empty_dir])
    output = capture(:stdout) { stats.to_s }

    assert_match(/\| Empty\s+\|\s+0 \|\s+0 \|\s+0 \|\s+0 \|\s+0 \|\s+0 \|/, output)
    assert_no_match(/\| Total\s+\|/, output)
    assert_match(/Code LOC: 0\s+Test LOC: 0\s+Code to Test Ratio: 1:NaN/, output)
  end

  test "skips directory entries that do not match the statistics pattern" do
    stats = Rails::CodeStatistics.allocate

    dir_singleton = class << Dir; self; end
    file_singleton = class << File; self; end
    original_foreach = Dir.method(:foreach)
    original_directory = File.method(:directory?)
    dir_singleton.define_method(:foreach) { |_directory, &block| block.call(nil) }
    file_singleton.define_method(:directory?) { |_path| false }

    calculator = stats.send(:calculate_directory_statistics, @tmp_path)
    assert_equal 0, calculator.lines
  ensure
    dir_singleton.define_method(:foreach) { |*args, **kwargs, &block| original_foreach.call(*args, **kwargs, &block) } if original_foreach
    file_singleton.define_method(:directory?) { |*args, **kwargs, &block| original_directory.call(*args, **kwargs, &block) } if original_directory
  end
end
