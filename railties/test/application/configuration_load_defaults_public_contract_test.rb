# frozen_string_literal: true

require "abstract_unit"
require "rails/application/configuration"

class ApplicationConfigurationLoadDefaultsPublicContractTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("rails-configuration-load-defaults"))
    @config = Rails::Application::Configuration.new(@root)
    @old_env = Rails.env
    @old_regexp_timeout = Regexp.timeout if Regexp.respond_to?(:timeout)
  end

  teardown do
    Rails.env = @old_env
    Regexp.timeout = @old_regexp_timeout if Regexp.respond_to?(:timeout=)
    FileUtils.rm_rf(@root)
  end

  test "load defaults applies cumulative framework defaults through current versions" do
    @config.assets = ActiveSupport::OrderedOptions.new
    @config.load_defaults "8.2"

    assert_equal "8.2", @config.loaded_config_version
    assert_equal false, @config.add_autoload_paths_to_load_path
    assert_equal true, @config.precompile_filter_parameters
    assert_equal false, @config.assets.unknown_asset_fallback
    assert_equal false, @config.action_controller.escape_json_responses
    assert_equal :raise, @config.action_controller.action_on_path_relative_redirect
    assert_equal :header_only, @config.action_controller.forgery_protection_verification_strategy
    assert_equal :exception, @config.action_controller.default_protect_from_forgery_with
    assert_equal :array, @config.action_controller.rescue_from_event_backtrace
    assert_equal true, @config.action_dispatch.strict_freshness
    assert_equal true, @config.action_dispatch.strict_accept_header
    assert_equal "nosniff", @config.action_dispatch.default_headers["X-Content-Type-Options"]
    assert_equal false, @config.active_support.escape_js_separators_in_json
    assert_equal :ruby, @config.action_view.render_tracker
    assert_equal true, @config.action_view.remove_hidden_field_autocomplete
    assert_equal :immediately, @config.active_storage.analyze
    assert_equal true, @config.active_job.enqueue_after_transaction_commit
  end

  test "load defaults accepts numeric versions and reports unknown versions" do
    Rails.env = "production"
    minimal_config = self.class.minimal_configuration_class.new(@root)
    hide_nokogiri_html5_constant { minimal_config.load_defaults 7.1 }
    assert_equal :html4, minimal_config.dom_testing_default_html_version
    assert_nil minimal_config.log_file_size

    Rails.env = @old_env
    @config.load_defaults 7.2

    assert_equal 7.2, @config.loaded_config_version
    assert_equal true, @config.yjit
    assert_equal %w( image/png image/jpeg image/gif image/webp ), @config.active_storage.web_image_content_types

    if Regexp.respond_to?(:timeout=)
      Regexp.timeout = nil
      @config.load_defaults "8.0"
      assert_equal 1, Regexp.timeout

      Regexp.timeout = 2
      @config.load_defaults "8.0"
      assert_equal 2, Regexp.timeout

      original_regexp_respond_to = Regexp.method(:respond_to?)
      Regexp.define_singleton_method(:respond_to?) do |name, include_private = false|
        name == :timeout= ? false : original_regexp_respond_to.call(name, include_private)
      end
      @config.load_defaults "8.0"
    end

    Regexp.define_singleton_method(:respond_to?) { |*args, **kwargs, &block| original_regexp_respond_to.call(*args, **kwargs, &block) } if original_regexp_respond_to

    error = assert_raises(RuntimeError) { @config.load_defaults "9.9" }
    assert_equal 'Unknown version "9.9"', error.message
  end

  test "load defaults skips framework specific settings when those configs are absent" do
    config = Class.new(Rails::Application::Configuration) do
      def respond_to?(name, include_private = false)
        return false if %i[action_controller active_record action_dispatch action_view action_mailer active_storage action_mailbox active_job action_text active_support assets].include?(name)

        super
      end
    end.new(@root)

    config.load_defaults "8.2"

    assert_equal "8.2", config.loaded_config_version
    assert_equal false, config.add_autoload_paths_to_load_path
    assert_equal true, config.precompile_filter_parameters
    assert_equal !Rails.env.local?, config.yjit
  end

  private
    def self.minimal_configuration_class
      @minimal_configuration_class ||= Class.new(Rails::Application::Configuration) do
        def respond_to?(name, include_private = false)
          return false if %i[action_controller active_record action_dispatch action_view action_mailer active_storage action_mailbox active_job action_text active_support assets].include?(name)

          super
        end
      end
    end

    def hide_nokogiri_html5_constant
      return yield unless defined?(Nokogiri::HTML5)

      html5 = Nokogiri.send(:remove_const, :HTML5)
      yield
    ensure
      Nokogiri.const_set(:HTML5, html5) if html5
    end
end
