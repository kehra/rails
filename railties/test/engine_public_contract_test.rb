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
