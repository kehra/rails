# frozen_string_literal: true

require "test_helper"
require "database/setup"
require "active_storage/transformers/null_transformer"
require "active_storage/transformers/vips"
require "active_storage/transformers/image_magick"
require "tmpdir"

class ActiveStorage::EngineTest < ActiveSupport::TestCase
  test "all default content types are recognized by marcel" do
    ActiveStorage.variable_content_types.each do |content_type|
      assert_equal content_type, Marcel::Magic.new(content_type).type
    end

    ActiveStorage.web_image_content_types.each do |content_type|
      assert_equal content_type, Marcel::Magic.new(content_type).type
    end

    ActiveStorage.content_types_to_serve_as_binary.each do |content_type|
      assert_equal content_type, Marcel::Magic.new(content_type).type
    end

    ActiveStorage.content_types_allowed_inline.each do |content_type|
      assert_equal content_type, Marcel::Magic.new(content_type).type
    end
  end

  test "image/bmp is a default content type" do
    assert_includes ActiveStorage.variable_content_types, "image/bmp"
  end

  test "version returns the loaded gem version" do
    assert_instance_of Gem::Version, ActiveStorage.version
    assert_equal ActiveStorage.gem_version, ActiveStorage.version
  end

  test "true is the default touch_attachment_records value" do
    assert_equal true, ActiveStorage.touch_attachment_records
  end

  test "engine selects configured variant transformers" do
    assert_engine_variant_transformer :disabled, ActiveStorage::Transformers::NullTransformer
    assert_engine_variant_transformer :vips, ActiveStorage::Transformers::Vips
    assert_engine_variant_transformer :mini_magick, ActiveStorage::Transformers::ImageMagick
    assert_engine_variant_transformer :unknown, nil
  end

  test "engine warns when configured variant transformer dependencies are missing" do
    assert_engine_variant_transformer_load_error :vips, :Vips, "libvips is missing", /requires the libvips library/
    assert_engine_variant_transformer_load_error :mini_magick, :ImageMagick, "image_processing is missing", /Generating image variants require the image_processing gem/

    assert_raises(LoadError) do
      assert_engine_variant_transformer_load_error :vips, :Vips, "unexpected transformer failure", nil
    end
  end

  test "engine loads service configurations from storage yml" do
    app = Rails.application
    previous_configurations = app.config.active_storage.service_configurations
    previous_service = app.config.active_storage.service
    previous_blob_services = ActiveStorage::Blob.services
    previous_blob_service = ActiveStorage::Blob.service

    app.config.active_storage.service_configurations = nil
    app.config.active_storage.service = nil

    run_engine_initializer "active_storage.services", app

    assert_instance_of ActiveStorage::Service::DiskService, ActiveStorage::Blob.services.fetch(:test)
  ensure
    app.config.active_storage.service_configurations = previous_configurations
    app.config.active_storage.service = previous_service
    ActiveStorage::Blob.services = previous_blob_services
    ActiveStorage::Blob.service = previous_blob_service
  end

  test "engine loads environment-specific storage configuration before fallback" do
    app = Rails.application
    previous_configurations = app.config.active_storage.service_configurations
    previous_service = app.config.active_storage.service
    previous_blob_services = ActiveStorage::Blob.services
    previous_blob_service = ActiveStorage::Blob.service

    Dir.mktmpdir do |dir|
      root = Pathname.new(dir)
      FileUtils.mkdir_p root.join("config/storage")
      File.write root.join("config/storage/test.yml"), <<~YAML
        local:
          service: Disk
          root: #{root.join("tmp/storage")}
      YAML

      app.config.active_storage.service_configurations = nil
      app.config.active_storage.service = nil

      Rails.stub(:root, root) do
        run_engine_initializer "active_storage.services", app
      end
    end

    assert_instance_of ActiveStorage::Service::DiskService, ActiveStorage::Blob.services.fetch(:local)
  ensure
    app.config.active_storage.service_configurations = previous_configurations
    app.config.active_storage.service = previous_service
    ActiveStorage::Blob.services = previous_blob_services
    ActiveStorage::Blob.service = previous_blob_service
  end

  test "engine raises when storage configuration is missing" do
    app = Rails.application
    previous_configurations = app.config.active_storage.service_configurations

    Dir.mktmpdir do |dir|
      app.config.active_storage.service_configurations = nil

      Rails.stub(:root, Pathname.new(dir)) do
        error = assert_raises(RuntimeError) do
          run_engine_initializer "active_storage.services", app
        end

        assert_match "Couldn't find Active Storage configuration", error.message
      end
    end
  ensure
    app.config.active_storage.service_configurations = previous_configurations
  end

  test "engine assigns configured service choice" do
    app = Rails.application
    previous_configurations = app.config.active_storage.service_configurations
    previous_service = app.config.active_storage.service
    previous_blob_services = ActiveStorage::Blob.services
    previous_blob_service = ActiveStorage::Blob.service

    app.config.active_storage.service_configurations = {
      "local" => { "service" => "Disk", "root" => Rails.root.join("tmp/storage").to_s }
    }
    app.config.active_storage.service = :local

    run_engine_initializer "active_storage.services", app

    assert_instance_of ActiveStorage::Service::DiskService, ActiveStorage::Blob.service
  ensure
    app.config.active_storage.service_configurations = previous_configurations
    app.config.active_storage.service = previous_service
    ActiveStorage::Blob.services = previous_blob_services
    ActiveStorage::Blob.service = previous_blob_service
  end

  test "engine applies multiple file field configuration when present" do
    app = Rails.application
    previous_config = app.config.active_storage.multiple_file_field_include_hidden
    previous_helper_value = ActionView::Helpers::FormHelper.multiple_file_field_include_hidden

    app.config.active_storage.multiple_file_field_include_hidden = false
    run_engine_initializer "action_view.configuration", app
    ActiveSupport.run_load_hooks(:action_view, ActionView::Base)

    assert_equal false, ActionView::Helpers::FormHelper.multiple_file_field_include_hidden

    app.config.active_storage.multiple_file_field_include_hidden = nil
    run_engine_initializer "action_view.configuration", app
    ActiveSupport.run_load_hooks(:action_view, ActionView::Base)

    assert_equal false, ActionView::Helpers::FormHelper.multiple_file_field_include_hidden
  ensure
    app.config.active_storage.multiple_file_field_include_hidden = previous_config
    ActionView::Helpers::FormHelper.multiple_file_field_include_hidden = previous_helper_value
  end

  test "engine adds assets when configured to precompile them" do
    app = Rails.application
    previous_precompile = app.config.assets.precompile.dup if app.config.respond_to?(:assets)
    previous_precompile_assets = app.config.active_storage.precompile_assets

    app.config.active_storage.precompile_assets = true
    run_engine_initializer "active_storage.asset", app

    assert_includes app.config.assets.precompile, "activestorage"
    assert_includes app.config.assets.precompile, "activestorage.esm"

    app.config.active_storage.precompile_assets = false
    app.config.assets.precompile.delete("activestorage")
    app.config.assets.precompile.delete("activestorage.esm")
    run_engine_initializer "active_storage.asset", app

    assert_not_includes app.config.assets.precompile, "activestorage"
    assert_not_includes app.config.assets.precompile, "activestorage.esm"
  ensure
    app.config.assets.precompile = previous_precompile if previous_precompile
    app.config.active_storage.precompile_assets = previous_precompile_assets
  end

  test "engine sets fixture file path from active record fixture hook" do
    previous_path = ActiveStorage::FixtureSet.file_fixture_path
    previous_env_path = ENV["FIXTURES_PATH"]
    previous_env_dir = ENV["FIXTURES_DIR"]

    ENV["FIXTURES_PATH"] = "custom/fixtures"
    ENV["FIXTURES_DIR"] = "nested"
    ActiveStorage::FixtureSet.file_fixture_path = nil

    run_engine_initializer "active_storage.fixture_set"
    ActiveSupport.run_load_hooks(:active_record_fixture_set)

    ENV.delete("FIXTURES_PATH")
    ENV.delete("FIXTURES_DIR")
    ActiveStorage::FixtureSet.file_fixture_path = nil
    run_engine_initializer "active_storage.fixture_set"
    ActiveSupport.run_load_hooks(:active_record_fixture_set)

    assert_equal ActiveSupport::TestCase.file_fixture_path, ActiveStorage::FixtureSet.file_fixture_path
  ensure
    ActiveStorage::FixtureSet.file_fixture_path = previous_path
    ENV["FIXTURES_PATH"] = previous_env_path
    ENV["FIXTURES_DIR"] = previous_env_dir
  end

  private
    def assert_engine_variant_transformer(processor, transformer)
      app = Rails.application
      previous_processor = app.config.active_storage.variant_processor
      previous_active_storage_processor = ActiveStorage.variant_processor
      previous_transformer = ActiveStorage.variant_transformer

      app.config.active_storage.variant_processor = processor
      run_engine_initializer "active_storage.configs", app

      if transformer.nil?
        assert_nil ActiveStorage.variant_transformer
      else
        assert_equal transformer, ActiveStorage.variant_transformer
      end
    ensure
      app.config.active_storage.variant_processor = previous_processor
      ActiveStorage.variant_processor = previous_active_storage_processor
      ActiveStorage.variant_transformer = previous_transformer
    end

    def assert_engine_variant_transformer_load_error(processor, transformer_name, message, warning_pattern)
      app = Rails.application
      previous_processor = app.config.active_storage.variant_processor
      previous_active_storage_processor = ActiveStorage.variant_processor
      previous_config_logger = app.config.active_storage.logger
      previous_transformer = ActiveStorage.variant_transformer
      previous_logger = ActiveStorage.logger
      transformer = ActiveStorage::Transformers.send(:remove_const, transformer_name)
      warnings = []
      logger = Object.new
      logger.define_singleton_method(:warn) { |message| warnings << message }

      ActiveStorage::Transformers.define_singleton_method(:const_missing) do |name|
        raise LoadError, message if name == transformer_name
        super(name)
      end

      app.config.active_storage.variant_processor = processor
      app.config.active_storage.logger = logger
      ActiveStorage.logger = logger

      if warning_pattern
        run_engine_initializer "active_storage.configs", app
        assert_match warning_pattern, warnings.join("\n")
      else
        run_engine_initializer "active_storage.configs", app
      end
    ensure
      ActiveStorage::Transformers.singleton_class.remove_method(:const_missing) if ActiveStorage::Transformers.singleton_class.method_defined?(:const_missing)
      ActiveStorage::Transformers.const_set(transformer_name, transformer) if transformer && !ActiveStorage::Transformers.const_defined?(transformer_name, false)
      app.config.active_storage.variant_processor = previous_processor
      ActiveStorage.variant_processor = previous_active_storage_processor
      app.config.active_storage.logger = previous_config_logger
      ActiveStorage.variant_transformer = previous_transformer
      ActiveStorage.logger = previous_logger
    end

    def run_engine_initializer(name, app = Rails.application)
      initializer = ActiveStorage::Engine.initializers.find { |candidate| candidate.name == name }
      ActiveStorage::Engine.instance_exec(app, &initializer.block)
    end
end
