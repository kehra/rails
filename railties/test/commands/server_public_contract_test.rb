# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/server/server_command"

class ServerPublicContractTest < ActiveSupport::TestCase
  setup do
    @previous_rails_env = ENV["RAILS_ENV"]
  end

  teardown do
    if @previous_rails_env.nil?
      ENV.delete("RAILS_ENV")
    else
      ENV["RAILS_ENV"] = @previous_rails_env
    end
  end

  test "options parser delegates to server command options" do
    options = Rails::Server::Options.new.parse!(%w[-p 4567 -b 127.0.0.1 --early-hints])

    assert_equal 4567, options[:Port]
    assert_equal "127.0.0.1", options[:Host]
    assert_equal true, options[:early_hints]
  end

  test "server exposes option parser middleware and default options" do
    server = Rails::Server.new(server: "webrick", Host: "127.0.0.1", Port: 3001, environment: "test")

    assert_instance_of Rails::Server::Options, server.opt_parser
    assert_equal [], server.middleware[:anything]
    assert_equal "webrick", server.default_options[:server]
    assert_equal "127.0.0.1", server.default_options[:Host]
  end

  test "server set environment does not overwrite existing rails env" do
    ENV.delete("RAILS_ENV")
    Rails::Server.new(environment: "production")
    assert_equal "production", ENV["RAILS_ENV"]

    ENV["RAILS_ENV"] = "test"
    Rails::Server.new(environment: "development")
    assert_equal "test", ENV["RAILS_ENV"]
  end

  test "served url uses scheme and is omitted for puma" do
    https_server = Rails::Server.new(server: "webrick", Host: "example.com", Port: 3443, SSLEnable: true, environment: "test")
    assert_equal "https://example.com:3443", https_server.served_url

    http_server = Rails::Server.new(server: "webrick", Host: "example.com", Port: 3000, environment: "test")
    assert_equal "http://example.com:3000", http_server.served_url

    puma_server = Rails::Server.new(Host: "127.0.0.1", Port: 3000, environment: "test")
    puma_server.define_singleton_method(:server) { "Rackup::Handler::Puma" }
    assert_nil puma_server.served_url
  end

  test "start prepares runtime and always runs optional after stop callback" do
    server = Rails::Server.new(environment: "development", log_stdout: true)
    calls = []
    server.define_singleton_method(:create_tmp_directories) { calls << :create_tmp_directories }
    server.define_singleton_method(:setup_dev_caching) { calls << :setup_dev_caching }
    server.define_singleton_method(:log_to_stdout) { calls << :log_to_stdout }

    with_rackup_server_start(calls) do
      server.start(-> { calls << :after_stop })
    end

    assert_equal [ :create_tmp_directories, :setup_dev_caching, :log_to_stdout, :rackup_start, :after_stop ], calls
  end

  test "start skips stdout logging and callback when not configured" do
    server = Rails::Server.new(environment: "test", log_stdout: false)
    calls = []
    server.define_singleton_method(:create_tmp_directories) { calls << :create_tmp_directories }
    server.define_singleton_method(:setup_dev_caching) { calls << :setup_dev_caching }
    server.define_singleton_method(:log_to_stdout) { calls << :log_to_stdout }

    with_rackup_server_start(calls) do
      server.start
    end

    assert_equal [ :create_tmp_directories, :setup_dev_caching, :rackup_start ], calls
  end

  private
    def with_rackup_server_start(calls)
      original = Rackup::Server.instance_method(:start)
      Rackup::Server.define_method(:start) { calls << :rackup_start }
      yield
    ensure
      Rackup::Server.define_method(:start, original)
    end
end
