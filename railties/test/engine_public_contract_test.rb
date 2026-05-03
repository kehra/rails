# frozen_string_literal: true

require "abstract_unit"
require "rails/engine"

class EnginePublicContractTest < ActiveSupport::TestCase
  setup do
    @root = Pathname.new(Dir.mktmpdir("rails-engine-public-contract"))
    FileUtils.mkdir_p(@root.join("lib"))
  end

  teardown do
    FileUtils.rm_rf(@root)
  end

  test "inherited registers eager load namespace and root lookup uses lib flag" do
    before_namespaces = Rails::Railtie::Configuration.eager_load_namespaces.dup

    engine_class = build_engine_class
    FileUtils.mkdir_p(@root.join("app/models"))

    assert_includes Rails::Railtie::Configuration.eager_load_namespaces, engine_class
    assert_equal @root.realpath, engine_class.find_root(@root.join("app/models"))
  ensure
    Rails::Railtie::Configuration.eager_load_namespaces.replace(before_namespaces) if before_namespaces
  end

  test "class endpoint stores explicit rack app and instance endpoint falls back to routes" do
    engine_class = build_engine_class
    rack_endpoint = ->(_) { [ 204, {}, [] ] }

    assert_nil engine_class.endpoint
    assert_same rack_endpoint, engine_class.endpoint(rack_endpoint)

    engine = engine_class.instance
    assert_same rack_endpoint, engine.endpoint

    fallback_class = build_engine_class
    fallback = fallback_class.instance
    assert_same fallback.routes, fallback.endpoint
  end

  test "config routes env config railties and eager load expose memoized collaborators" do
    engine = build_engine_class.instance

    assert_same engine.config, engine.config
    assert_equal @root.realpath, engine.config.root
    assert_same engine.routes, engine.routes
    assert engine.routes?
    assert_same engine.env_config, engine.env_config
    assert_equal({}, engine.env_config)
    assert_same engine.railties, engine.railties
    assert_nil engine.eager_load!
  end

  test "configuration initializes defaults and memoized paths and yields generators" do
    engine = build_engine_class.instance
    config = engine.config

    assert_equal @root.realpath, config.root
    assert_kind_of Rails::Configuration::Generators, config.generators
    assert_kind_of Rails::Configuration::MiddlewareStackProxy, config.middleware
    assert_equal "javascript", config.javascript_path
    assert_equal ActionDispatch::Routing::RouteSet, config.route_set_class
    assert_nil config.default_scope
    assert_empty config.autoload_paths
    assert_empty config.autoload_once_paths
    assert_empty config.eager_load_paths

    yielded = nil
    generators = config.generators do |g|
      yielded = g
      g.orm :sequel
    end

    assert_same generators, yielded
    assert_same generators, config.generators
    assert_equal :sequel, generators.orm

    FileUtils.mkdir_p(@root.join("app/models"))
    paths = config.paths
    assert_same paths, config.paths
    assert_equal @root.realpath, paths.path
    assert_equal [ @root.join("app/models").to_s ], paths["app/models"].existent

    new_root = @root.join("nested")
    FileUtils.mkdir_p(new_root)
    config.root = new_root

    assert_equal new_root.realpath, config.root
    assert_equal new_root.realpath, config.paths.path

    config.autoload_paths << "custom/autoload"
    config.autoload_once_paths << "custom/once"
    config.eager_load_paths << "custom/eager"

    assert_includes config.send(:all_autoload_paths), "custom/autoload"
    assert_includes config.send(:all_autoload_once_paths), "custom/once"
    assert_includes config.send(:all_eager_load_paths), "custom/eager"
  end

  test "routes appends blocks and helpers paths report existing helper directories" do
    engine = build_engine_class.instance
    helper_dir = @root.join("app/helpers")
    FileUtils.mkdir_p(helper_dir)

    returned_routes = engine.routes do
      get "/engine_public_contract" => "engine_public_contract#index"
    end

    assert_same engine.routes, returned_routes
    assert_equal [ helper_dir.to_s ], engine.helpers_paths
  end

  test "helpers app call load seed find and namespace isolation expose public contracts" do
    engine_class = build_engine_class
    engine = engine_class.instance
    helper_dir = @root.join("app/helpers")
    FileUtils.mkdir_p(helper_dir)
    helper_file = helper_dir.join("engine_contract_helper.rb")
    File.write(helper_file, <<~RUBY)
      module EngineContractHelper
        def engine_contract_helper_method
          :engine_contract_helper
        end
      end
    RUBY
    load helper_file

    helpers = engine.helpers
    assert_same helpers, engine.helpers
    assert_includes helpers.instance_methods, :engine_contract_helper_method

    rack_endpoint = ->(env) { [ 200, { "X-Engine-Script-Name" => env["SCRIPT_NAME"].to_s }, [ env["engine.extra"] ] ] }
    engine_class.endpoint rack_endpoint
    engine.env_config["engine.extra"] = "merged"

    response = engine.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/", "SCRIPT_NAME" => "/mounted", "rack.input" => StringIO.new)

    assert_equal 200, response[0]
    assert_equal [ "merged" ], response[2]
    assert_same engine.app, engine.app

    seeds = []
    FileUtils.mkdir_p(@root.join("db"))
    File.write(@root.join("db/seeds.rb"), "$engine_public_contract_seed_loaded = true")
    engine_class.set_callback(:load_seed, :before) { seeds << :before }
    engine.load_seed

    assert $engine_public_contract_seed_loaded
    assert_equal [ :before ], seeds
    with_engine_subclasses([ engine_class ]) do
      assert_same engine, Rails::Engine.find(@root)
      assert_nil Rails::Engine.find(@root.join("missing"))
    end

    namespace = Module.new
    namespace.define_singleton_method(:name) { "EngineContract" }
    engine_class.isolate_namespace(namespace)

    assert engine_class.isolated?
    assert_equal "engine_contract", engine_class.engine_name
    assert_equal({ module: "engine_contract" }, engine_class.config.default_scope)
    assert_same engine_class, namespace.railtie_namespace
    assert_equal "engine_contract_", namespace.table_name_prefix
    assert namespace.use_relative_model_naming?
    assert_equal engine.helpers_paths, namespace.railtie_helpers_paths
    assert_same engine.routes.url_helpers, namespace.railtie_routes_url_helpers

    with_active_record_base_prefix("global_") do
      ActiveSupport.run_load_hooks(:active_record)
      assert_equal "global_engine_contract_", namespace.table_name_prefix
    end

    existing = Module.new
    existing.define_singleton_method(:name) { "ExistingContract" }
    existing.define_singleton_method(:railtie_namespace) { :existing_railtie }
    existing.define_singleton_method(:table_name_prefix) { "existing_" }
    existing.define_singleton_method(:use_relative_model_naming?) { false }
    existing.define_singleton_method(:railtie_helpers_paths) { [ "existing" ] }
    existing.define_singleton_method(:railtie_routes_url_helpers) { :existing_routes }
    build_engine_class.isolate_namespace(existing)

    assert_equal :existing_railtie, existing.railtie_namespace
    assert_equal "existing_", existing.table_name_prefix
    assert_not existing.use_relative_model_naming?
    assert_equal [ "existing" ], existing.railtie_helpers_paths
    assert_equal :existing_routes, existing.railtie_routes_url_helpers

    partial_existing = Module.new
    partial_existing.define_singleton_method(:name) { "PartialExistingContract" }
    partial_existing.define_singleton_method(:table_name_prefix) { "partial_existing_" }
    partial_existing.define_singleton_method(:use_relative_model_naming?) { false }
    partial_existing.define_singleton_method(:railtie_helpers_paths) { [ "partial_existing" ] }
    partial_existing.define_singleton_method(:railtie_routes_url_helpers) { :partial_existing_routes }
    build_engine_class.isolate_namespace(partial_existing)

    assert_operator partial_existing.railtie_namespace, :<=, Rails::Engine
    assert_equal "partial_existing_", partial_existing.table_name_prefix
    assert_not partial_existing.use_relative_model_naming?
    assert_equal [ "partial_existing" ], partial_existing.railtie_helpers_paths
    assert_equal :partial_existing_routes, partial_existing.railtie_routes_url_helpers

    FileUtils.rm_f(@root.join("db/seeds.rb"))
    no_seed_engine = build_engine_class.instance
    assert_nil no_seed_engine.load_seed
  ensure
    $engine_public_contract_seed_loaded = false
  end

  test "load console runner server tasks and generators run registered hooks and return self" do
    engine_class = build_engine_class
    events = []
    engine_class.console { |app| events << [ :console, app ] }
    engine_class.runner { |app| events << [ :runner, app ] }
    engine_class.server { |app| events << [ :server, app ] }
    engine_class.rake_tasks { |app| events << [ :tasks, app ] }
    engine_class.generators { |app| events << [ :generators, app ] }
    engine = engine_class.instance

    with_generators_configure_spy(events) do
      assert_same engine, engine.load_console(:console_app)
      assert_same engine, engine.load_runner(:runner_app)
      assert_same engine, engine.load_server(:server_app)
      assert_same engine, engine.load_tasks(:tasks_app)
      assert_same engine, engine.load_generators(engine)
    end

    assert_includes events, [ :console, :console_app ]
    assert_includes events, [ :runner, :runner_app ]
    assert_includes events, [ :server, :server_app ]
    assert_includes events, [ :tasks, :tasks_app ]
    assert_includes events, [ :generators, engine ]
    assert_includes events, [ :configure_generators, engine.config.generators ]
  end

  private
    def build_engine_class
      root = @root
      Class.new(Rails::Engine).tap do |klass|
        klass.called_from = root.to_s
      end
    end

    def with_engine_subclasses(subclasses)
      singleton = class << Rails::Engine; self; end
      original = Rails::Engine.method(:subclasses)
      singleton.define_method(:subclasses) { subclasses }
      yield
    ensure
      singleton.define_method(:subclasses) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end

    def with_active_record_base_prefix(prefix)
      original_active_record = Object.const_defined?(:ActiveRecord) ? Object.const_get(:ActiveRecord) : nil
      Object.send(:remove_const, :ActiveRecord) if Object.const_defined?(:ActiveRecord)
      active_record = Module.new
      base = Class.new
      base.define_singleton_method(:table_name_prefix) { prefix }
      active_record.const_set(:Base, base)
      Object.const_set(:ActiveRecord, active_record)
      yield
    ensure
      Object.send(:remove_const, :ActiveRecord) if Object.const_defined?(:ActiveRecord)
      Object.const_set(:ActiveRecord, original_active_record) if original_active_record
    end

    def with_generators_configure_spy(events)
      require "rails/generators"
      singleton = class << Rails::Generators; self; end
      original = Rails::Generators.method(:configure!)
      singleton.define_method(:configure!) { |config| events << [ :configure_generators, config ] }
      yield
    ensure
      singleton.define_method(:configure!) { |*args, **kwargs, &block| original.call(*args, **kwargs, &block) }
    end
end
