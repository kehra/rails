# frozen_string_literal: true

require "abstract_unit"
require "rails/application/default_middleware_stack"

class DefaultMiddlewareStackPublicContractTest < ActiveSupport::TestCase
  setup do
    @public_root = Dir.mktmpdir("rails-default-middleware-public")
  end

  teardown do
    FileUtils.rm_rf(@public_root)
  end

  test "initializes with app config and paths collaborators" do
    app = App.new
    config = full_config
    paths = paths_config

    stack = Rails::Application::DefaultMiddlewareStack.new(app, config, paths)

    assert_same app, stack.app
    assert_same config, stack.config
    assert_same paths, stack.paths
  end

  test "builds middleware stack with optional full application features" do
    app = App.new
    config = full_config
    stack = Rails::Application::DefaultMiddlewareStack.new(app, config, paths_config).build_stack

    middlewares = stack.map(&:klass)

    assert_includes middlewares, ActionDispatch::HostAuthorization
    assert_includes middlewares, ActionDispatch::AssumeSSL
    assert_includes middlewares, ActionDispatch::SSL
    assert_includes middlewares, Rack::Sendfile
    assert_includes middlewares, ActionDispatch::Static
    assert_includes middlewares, Rack::Lock
    assert_includes middlewares, ActionDispatch::Executor
    assert_includes middlewares, ActionDispatch::ServerTiming
    assert_includes middlewares, Rack::MethodOverride
    assert_includes middlewares, Rails::Rack::SilenceRequest
    assert_includes middlewares, Rails::Rack::Logger
    assert_includes middlewares, ActionDispatch::ActionableExceptions
    assert_includes middlewares, ActionDispatch::Reloader
    assert_includes middlewares, ActionDispatch::Cookies
    assert_includes middlewares, ActionDispatch::Session::CookieStore
    assert_includes middlewares, ActionDispatch::Flash
    assert_includes middlewares, ActionDispatch::ContentSecurityPolicy::Middleware
    assert_includes middlewares, ActionDispatch::PermissionsPolicy::Middleware
    assert_includes middlewares, Rack::TempfileReaper

    session_middleware = stack.find { |middleware| middleware.klass == ActionDispatch::Session::CookieStore }
    assert_equal true, config.session_options[:secure]
    assert_equal config.session_options, session_middleware.args.first
  end

  test "builds rack cache session variants permissions variants and active record middleware" do
    config = full_config
    config.action_dispatch.rack_cache = true
    config.session_options = { secure: false }
    config.permissions_policy = nil
    stack = Rails::Application::DefaultMiddlewareStack.new(App.new, config, paths_config).build_stack
    middlewares = stack.map(&:klass)

    assert_includes middlewares, Rack::Cache
    assert_includes middlewares, ActionDispatch::Session::CookieStore
    assert_not_includes middlewares, ActionDispatch::PermissionsPolicy::Middleware
    assert_equal false, config.session_options[:secure]

    config_with_active_record = full_config_with_active_record(
      database_selector: { delay: 2.seconds },
      shard_resolver: :resolver,
      shard_selector: { lock: true }
    )
    stack = Rails::Application::DefaultMiddlewareStack.new(App.new, config_with_active_record, paths_config).build_stack
    middlewares = stack.map(&:klass)

    assert_includes middlewares, ActiveRecord::Middleware::DatabaseSelector
    assert_includes middlewares, ActiveRecord::Middleware::ShardSelector

    config_without_active_record_options = full_config_with_active_record(database_selector: nil, shard_resolver: nil, shard_selector: nil)
    stack = Rails::Application::DefaultMiddlewareStack.new(App.new, config_without_active_record_options, paths_config).build_stack
    middlewares = stack.map(&:klass)

    assert_not_includes middlewares, ActiveRecord::Middleware::DatabaseSelector
    assert_not_includes middlewares, ActiveRecord::Middleware::ShardSelector
  end

  test "builds lean api stack without optional browser middleware" do
    stack = Rails::Application::DefaultMiddlewareStack.new(App.new, api_config, paths_config).build_stack

    middlewares = stack.map(&:klass)

    assert_not_includes middlewares, ActionDispatch::HostAuthorization
    assert_not_includes middlewares, ActionDispatch::AssumeSSL
    assert_not_includes middlewares, ActionDispatch::SSL
    assert_not_includes middlewares, Rack::Sendfile
    assert_not_includes middlewares, ActionDispatch::Static
    assert_not_includes middlewares, Rack::Lock
    assert_not_includes middlewares, Rack::MethodOverride
    assert_not_includes middlewares, Rails::Rack::SilenceRequest
    assert_not_includes middlewares, ActionDispatch::ActionableExceptions
    assert_not_includes middlewares, ActionDispatch::Reloader
    assert_not_includes middlewares, ActionDispatch::Cookies
    assert_not_includes middlewares, ActionDispatch::Session::CookieStore
    assert_not_includes middlewares, ActionDispatch::Flash
    assert_not_includes middlewares, ActionDispatch::ContentSecurityPolicy::Middleware
    assert_not_includes middlewares, ActionDispatch::PermissionsPolicy::Middleware
    assert_not_includes middlewares, Rack::TempfileReaper

    assert_includes middlewares, ActionDispatch::Executor
    assert_includes middlewares, Rack::Runtime
    assert_includes middlewares, ActionDispatch::RequestId
    assert_includes middlewares, ActionDispatch::RemoteIp
    assert_includes middlewares, ActionDispatch::ShowExceptions
    assert_includes middlewares, ActionDispatch::DebugExceptions
    assert_includes middlewares, ActionDispatch::Callbacks
    assert_includes middlewares, Rack::Head
    assert_includes middlewares, Rack::ConditionalGet
    assert_includes middlewares, Rack::ETag
  end

  private
    App = Struct.new(:executor, :reloader) do
      def initialize
        super(:executor, :reloader)
      end
    end

    unless defined?(::ActiveRecord::Middleware::DatabaseSelector)
      module ::ActiveRecord
        module Middleware
          DatabaseSelector = Class.new
          ShardSelector = Class.new
        end
      end
    end

    Config = Struct.new(
      :hosts, :host_authorization, :assume_ssl, :force_ssl, :ssl_options,
      :action_dispatch, :public_file_server, :allow_concurrency,
      :server_timing, :api_only, :silence_healthcheck_path, :log_tags,
      :debug_exception_response_format, :consider_all_requests_local,
      :session_store, :session_options, :permissions_policy,
      :exceptions_app, keyword_init: true
    ) do
      def reloading_enabled?
        @reloading_enabled
      end

      def reloading_enabled=(value)
        @reloading_enabled = value
      end
    end

    ActionDispatchConfig = Struct.new(
      :ssl_default_redirect_status, :x_sendfile_header, :request_id_header,
      :ip_spoofing_check, :trusted_proxies, :rack_cache, keyword_init: true
    )

    ConfigWithActiveRecord = Class.new(Config) do
      attr_accessor :active_record
    end

    ActiveRecordConfig = Struct.new(:database_selector, :database_resolver, :database_resolver_context, :shard_resolver, :shard_selector, keyword_init: true)

    PublicFileServerConfig = Struct.new(:enabled, :headers, :index_name, keyword_init: true)

    def full_config
      Config.new(
        hosts: [ "example.test" ],
        host_authorization: { exclude: ->(_) { false } },
        assume_ssl: true,
        force_ssl: true,
        ssl_options: { secure_cookies: true },
        action_dispatch: ActionDispatchConfig.new(
          ssl_default_redirect_status: 308,
          x_sendfile_header: "X-Sendfile",
          request_id_header: "X-Request-Id",
          ip_spoofing_check: true,
          trusted_proxies: [],
          rack_cache: false
        ),
        public_file_server: PublicFileServerConfig.new(enabled: true, headers: { "Cache-Control" => "public" }, index_name: "home"),
        allow_concurrency: false,
        server_timing: true,
        api_only: false,
        silence_healthcheck_path: "/up",
        log_tags: [ :request_id ],
        debug_exception_response_format: :default,
        consider_all_requests_local: true,
        session_store: ActionDispatch::Session::CookieStore,
        session_options: {},
        permissions_policy: ActionDispatch::PermissionsPolicy.new,
        exceptions_app: ->(_) { [ 500, {}, [] ] }
      ).tap { |config| config.reloading_enabled = true }
    end

    def full_config_with_active_record(database_selector:, shard_resolver:, shard_selector:)
      config = ConfigWithActiveRecord.new(**full_config.to_h)
      config.reloading_enabled = true
      config.active_record = ActiveRecordConfig.new(
        database_selector: database_selector,
        database_resolver: :database_resolver,
        database_resolver_context: :database_resolver_context,
        shard_resolver: shard_resolver,
        shard_selector: shard_selector
      )
      config
    end

    def api_config
      Config.new(
        hosts: [],
        host_authorization: {},
        assume_ssl: false,
        force_ssl: false,
        ssl_options: {},
        action_dispatch: ActionDispatchConfig.new(
          ssl_default_redirect_status: 301,
          x_sendfile_header: nil,
          request_id_header: "X-Request-Id",
          ip_spoofing_check: false,
          trusted_proxies: [],
          rack_cache: false
        ),
        public_file_server: PublicFileServerConfig.new(enabled: false, headers: nil, index_name: "index"),
        allow_concurrency: true,
        server_timing: false,
        api_only: true,
        silence_healthcheck_path: nil,
        log_tags: [],
        debug_exception_response_format: :api,
        consider_all_requests_local: false,
        session_store: nil,
        session_options: {},
        permissions_policy: nil,
        exceptions_app: nil
      ).tap { |config| config.reloading_enabled = false }
    end

    def paths_config
      { "public" => [ @public_root ] }
    end
end
