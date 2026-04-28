# frozen_string_literal: true

require_relative "abstract_unit"

module ActiveSupport
  class EditorTest < ActiveSupport::TestCase
    setup do
      Editor.reset
    end

    teardown do
      Editor.reset
    end

    def test_current
      with_env("EDITOR" => nil, "RAILS_EDITOR" => nil) do
        assert_nil Editor.current
      end

      with_env("EDITOR" => "mate", "RAILS_EDITOR" => nil) do
        assert_equal "txmt://open?url=file://foo.rb&line=42", Editor.current.url_for("foo.rb", 42)
      end

      with_env("EDITOR" => "mate", "RAILS_EDITOR" => "unknown") do
        assert_nil Editor.current
      end

      with_env("EDITOR" => "code", "RAILS_EDITOR" => "mate") do
        assert_equal "txmt://open?url=file://foo.rb&line=42", Editor.current.url_for("foo.rb", 42)
      end
    end

    def test_current_caches_until_reset
      with_env("EDITOR" => "mate", "RAILS_EDITOR" => nil) do
        current = Editor.current
        ENV["EDITOR"] = "code"

        assert_same current, Editor.current
      end
    end

    def test_find_and_custom_registration
      Editor.register("custom", "custom://%s:%d", aliases: ["custom_alias"])

      assert_equal "custom://foo.rb:42", Editor.find("custom").url_for("foo.rb", 42)
      assert_same Editor.find("custom"), Editor.find("custom_alias")
    end

    private
      def with_env(kv)
        old_values = {}
        kv.each { |key, value| old_values[key], ENV[key] = ENV[key], value }
        yield
      ensure
        old_values.each { |key, value| ENV[key] = value }
        Editor.reset
      end
  end
end
