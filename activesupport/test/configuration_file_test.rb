# frozen_string_literal: true

require_relative "abstract_unit"

class ConfigurationFileTest < ActiveSupport::TestCase
  test "backtrace contains YAML path" do
    Tempfile.create do |file|
      file.write("wrong: <%= foo %>")
      file.flush

      error = assert_raises do
        ActiveSupport::ConfigurationFile.parse(file.path)
      end

      assert_match file.path, error.backtrace.first
    end
  end

  test "backtrace contains YAML path (when Pathname given)" do
    Tempfile.create do |file|
      file.write("wrong: <%= foo %>")
      file.flush

      error = assert_raises do
        ActiveSupport::ConfigurationFile.parse(Pathname(file.path))
      end

      assert_match file.path, error.backtrace.first
    end
  end

  test "load raw YAML" do
    Tempfile.create do |file|
      file.write("ok: 42")
      file.flush

      data = ActiveSupport::ConfigurationFile.parse(Pathname(file.path))
      assert_equal({ "ok" => 42 }, data)
    end
  end

  test "load ERB YAML with context" do
    Tempfile.create do |file|
      file.write("ok: <%= value %>")
      file.flush

      context = Object.new.instance_eval do
        value = 42
        binding
      end
      data = ActiveSupport::ConfigurationFile.parse(file.path, context: context)

      assert_equal({ "ok" => 42 }, data)
    end
  end

  test "empty ERB YAML returns empty hash" do
    Tempfile.create do |file|
      file.write("<% nil %>")
      file.flush

      assert_equal({}, ActiveSupport::ConfigurationFile.parse(file.path))
    end
  end

  test "YAML syntax errors include helpful indentation message" do
    Tempfile.create do |file|
      file.write("foo:\n\tbar: baz")
      file.flush

      error = assert_raises(RuntimeError) do
        ActiveSupport::ConfigurationFile.parse(file.path)
      end

      assert_match(/YAML syntax error occurred while parsing/, error.message)
      assert_match(/Tabs are not allowed/, error.message)
    end
  end

  test "warns when content contains invisible non-breaking spaces" do
    Tempfile.create do |file|
      file.write("ok: 42\u00A0")
      file.flush

      assert_output(nil, /contains invisible non-breaking spaces/) do
        ActiveSupport::ConfigurationFile.parse(file.path)
      end
    end
  end
end
