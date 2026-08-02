# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/i18n_railtie"
require "active_support/testing/constant_stubbing"
require "pathname"

class I18nRailtieTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::ConstantStubbing

  FakePath = Struct.new(:existent, :absolute_current, :extensions) do
    alias_method :expanded_files, :existent
  end

  class FakeFileWatcher
    attr_reader :load_path, :directories, :block, :executed

    def initialize(load_path, directories, &block)
      @load_path = load_path
      @directories = directories
      @block = block
      @executed = false
    end

    def execute_if_updated
      yield if block_given?
      @executed = true
    end
  end

  class FakeReloader
    attr_reader :to_run_blocks

    def initialize
      @to_run_blocks = []
    end

    def to_run(&block)
      @to_run_blocks << block
    end
  end

  setup do
    @old_inited = I18n::Railtie.instance_variable_get(:@i18n_inited)
    @old_backend = I18n.backend
    @old_fallbacks = I18n.fallbacks if I18n.respond_to?(:fallbacks)
    @old_exception_handler = I18n.exception_handler
    @old_enforce_available_locales = I18n.enforce_available_locales
    @old_load_path = I18n.load_path.dup

    I18n::Railtie.instance_variable_set(:@i18n_inited, false)
    I18n.backend = I18n::Backend::Simple.new
    I18n.exception_handler = I18n::ExceptionHandler.new
    I18n.enforce_available_locales = true
    I18n.load_path = []
  end

  teardown do
    I18n::Railtie.instance_variable_set(:@i18n_inited, @old_inited)
    I18n.backend = @old_backend
    I18n.fallbacks = @old_fallbacks if defined?(@old_fallbacks)
    I18n.exception_handler = @old_exception_handler
    I18n.enforce_available_locales = @old_enforce_available_locales
    I18n.load_path = @old_load_path
  end

  test "include_fallbacks_module includes fallbacks in current backend" do
    I18n.backend = Class.new(I18n::Backend::Simple).new

    I18n::Railtie.include_fallbacks_module

    assert_kind_of I18n::Backend::Fallbacks, I18n.backend
  end

  test "init_fallbacks accepts ordered options hash array and default locale" do
    options = ActiveSupport::OrderedOptions.new
    options.defaults = [:"en-US"]
    options.map = { ca: :es }

    I18n::Railtie.init_fallbacks(options)
    assert_equal [:en, :"en-US"], I18n.fallbacks[:en]
    assert_equal [:ca, :es, :"en-US", :en], I18n.fallbacks[:ca]

    I18n::Railtie.init_fallbacks([:fr])
    assert_equal [:en, :fr], I18n.fallbacks[:en]

    I18n::Railtie.init_fallbacks({ ca: :es })
    assert_equal [:ca, :es], I18n.fallbacks[:ca]

    I18n.enforce_available_locales = false
    I18n.default_locale = :en
    I18n::Railtie.init_fallbacks(true)
    assert_equal [:en], I18n.fallbacks[:en]
  end

  test "validate_fallbacks accepts supported values and rejects unexpected ones" do
    empty_options = ActiveSupport::OrderedOptions.new
    options = ActiveSupport::OrderedOptions.new
    options.defaults = [:en]

    assert_not I18n::Railtie.validate_fallbacks(empty_options)
    assert I18n::Railtie.validate_fallbacks(options)
    assert I18n::Railtie.validate_fallbacks(true)
    assert I18n::Railtie.validate_fallbacks([:en])
    assert I18n::Railtie.validate_fallbacks({ ca: :es })

    error = assert_raises(RuntimeError) { I18n::Railtie.validate_fallbacks(false) }
    assert_match(/Unexpected fallback type false/, error.message)
  end

  test "watched_dirs_with_extensions maps path metadata" do
    path = FakePath.new(["ignored"], "/app/config/locales", [".rb", ".yml"])

    assert_equal({ "/app/config/locales" => [".rb", ".yml"] }, I18n::Railtie.watched_dirs_with_extensions([path]))
  end

  test "railtie eager load hooks initialize i18n" do
    app = fake_app(reloading_enabled: false)

    I18n::Railtie.config.before_eager_load.first.first.call(app)
    I18n::Railtie.config.after_initialize.first.first.call(app)

    assert I18n::Railtie.instance_variable_get(:@i18n_inited)
  end

  test "setup_raise_on_missing_translations_config configures load hooks and exception handling" do
    app = fake_app(raise_on_missing_translations: true)
    action_view_helper = Class.new do
      class << self
        attr_accessor :raise_on_missing_translations
      end
    end
    action_view = Module.new
    helpers = Module.new
    helpers.const_set(:TranslationHelper, action_view_helper)
    action_view.const_set(:Helpers, helpers)
    active_model_translation = Module.new do
      class << self
        attr_accessor :raise_on_missing_translations
      end
    end
    active_model = Module.new
    active_model.const_set(:Translation, active_model_translation)

    stub_const(Object, :ActionView, action_view, exists: false) do
      stub_const(Object, :ActiveModel, active_model, exists: false) do
        I18n::Railtie.setup_raise_on_missing_translations_config(app, true)
        ActiveSupport.run_load_hooks(:action_view)
        ActiveSupport.run_load_hooks(:active_model_translation)
      end
    end

    assert_equal true, action_view_helper.raise_on_missing_translations
    assert_equal true, active_model_translation.raise_on_missing_translations
    assert_raises(I18n::MissingTranslationData) do
      I18n.exception_handler.call(I18n::MissingTranslation.new(:en, :missing, {}), :en, :missing, {})
    end
    assert_raises(I18n::MissingTranslationData) do
      I18n.exception_handler.call(I18n::MissingTranslationData.new(:en, :missing, {}), :en, :missing, {})
    end
  end

  test "setup_raise_on_missing_translations_config keeps custom exception handler and skips non strict active model setting" do
    handler = ->(*) { :handled }
    I18n.exception_handler = handler
    app = fake_app(raise_on_missing_translations: true)
    action_view_helper = Class.new do
      class << self
        attr_accessor :raise_on_missing_translations
      end
    end
    action_view = Module.new
    helpers = Module.new
    helpers.const_set(:TranslationHelper, action_view_helper)
    action_view.const_set(:Helpers, helpers)
    active_model_translation = Module.new do
      class << self
        attr_accessor :raise_on_missing_translations
      end
    end
    active_model = Module.new
    active_model.const_set(:Translation, active_model_translation)

    stub_const(Object, :ActionView, action_view, exists: false) do
      stub_const(Object, :ActiveModel, active_model, exists: false) do
        I18n::Railtie.setup_raise_on_missing_translations_config(app, false)
        ActiveSupport.run_load_hooks(:active_model_translation)
      end
    end

    assert_same handler, I18n.exception_handler
  end

  test "initialize_i18n applies configuration and reloader once" do
    railtie_path = FakePath.new(["/app/config/locales/en.yml"], "/app/config/locales", [".yml"])
    app = fake_app(
      fallbacks: true,
      enforce_available_locales: false,
      railties_load_path: [railtie_path],
      load_path: ["/engine/extra.yml", "/app/stale.yml"],
      default_locale: :en,
      raise_on_missing_translations: :strict,
      reloading_enabled: true,
    )

    old_root = Rails.method(:root) if Rails.respond_to?(:root)
    Rails.define_singleton_method(:root) { Pathname("/app") }
    I18n::Railtie.define_singleton_method(:require_unload_lock!) { @required_unload_lock = true }
    action_view = Module.new
    helpers = Module.new
    action_view_helper = Class.new do
      class << self
        attr_accessor :raise_on_missing_translations
      end
    end
    helpers.const_set(:TranslationHelper, action_view_helper)
    action_view.const_set(:Helpers, helpers)
    active_model_translation = Module.new do
      class << self
        attr_accessor :raise_on_missing_translations
      end
    end
    active_model = Module.new
    active_model.const_set(:Translation, active_model_translation)
    stub_const(Object, :ActionView, action_view, exists: false) do
      stub_const(Object, :ActiveModel, active_model, exists: false) do
        I18n::Railtie.initialize_i18n(app)
        app.reloaders.first.block.call
        app.reloader.to_run_blocks.first.call
        I18n::Railtie.initialize_i18n(app)
      end
    end

    assert_equal false, I18n.enforce_available_locales
    assert_includes I18n.load_path, "/app/config/locales/en.yml"
    assert_includes I18n.load_path, "/engine/extra.yml"
    assert_not_includes I18n.load_path, "/app/stale.yml"
    assert_equal 1, app.reloaders.size
    assert_equal({ "/app/config/locales" => [".yml"] }, app.reloaders.first.directories)
    assert_equal 1, app.reloader.to_run_blocks.size
    assert app.reloaders.first.executed
    assert I18n::Railtie.instance_variable_get(:@required_unload_lock)
  ensure
    if old_root
      Rails.define_singleton_method(:root, old_root)
    else
      Rails.singleton_class.remove_method(:root) if Rails.respond_to?(:root)
    end
  end

  test "initialize_i18n skips empty fallbacks and reloader when not reloading" do
    app = fake_app(fallbacks: ActiveSupport::OrderedOptions.new, enforce_available_locales: nil, reloading_enabled: false)

    I18n::Railtie.initialize_i18n(app)

    assert_equal true, I18n.enforce_available_locales
    assert_empty app.reloaders
  end

  private
    def fake_app(fallbacks: nil, enforce_available_locales: nil, railties_load_path: [], load_path: [], default_locale: nil, raise_on_missing_translations: nil, reloading_enabled: false)
      i18n_config = ActiveSupport::OrderedOptions.new
      i18n_config.fallbacks = fallbacks unless fallbacks.nil?
      i18n_config.enforce_available_locales = enforce_available_locales unless enforce_available_locales.nil?
      i18n_config.railties_load_path = railties_load_path unless railties_load_path.empty?
      i18n_config.load_path = load_path unless load_path.empty?
      i18n_config.default_locale = default_locale unless default_locale.nil?
      i18n_config.raise_on_missing_translations = raise_on_missing_translations unless raise_on_missing_translations.nil?

      config = ActiveSupport::OrderedOptions.new
      config.i18n = i18n_config
      config.file_watcher = FakeFileWatcher
      config.reloading_enabled = reloading_enabled
      config.define_singleton_method(:reloading_enabled?) { self.reloading_enabled }

      app = Object.new
      app.define_singleton_method(:config) { config }
      app.define_singleton_method(:reloaders) { @reloaders ||= [] }
      app.define_singleton_method(:reloader) { @reloader ||= FakeReloader.new }
      app
    end
end
