# frozen_string_literal: true

require "abstract_unit"
require "rails/rackup/server"

class RackupServerPublicContractTest < ActiveSupport::TestCase
  test "uses rackup server when rackup is available" do
    original_rackup = Rails.const_get(:Rackup) if Rails.const_defined?(:Rackup, false)
    rackup_had_server = ::Rackup.const_defined?(:Server, false)
    original_rackup_server = ::Rackup.const_get(:Server) if rackup_had_server
    server = Class.new
    ::Rackup.send(:remove_const, :Server) if rackup_had_server
    ::Rackup.const_set(:Server, server)
    Rails.send(:remove_const, :Rackup) if Rails.const_defined?(:Rackup, false)

    with_kernel_require("rackup/server" => true) do
      load File.expand_path("../lib/rails/rackup/server.rb", __dir__)
    end

    assert_same server, Rails::Rackup::Server
  ensure
    Rails.send(:remove_const, :Rackup) if Rails.const_defined?(:Rackup, false)
    Rails.const_set(:Rackup, original_rackup) if original_rackup
    ::Rackup.send(:remove_const, :Server) if defined?(::Rackup) && ::Rackup.const_defined?(:Server, false)
    ::Rackup.const_set(:Server, original_rackup_server) if defined?(::Rackup) && rackup_had_server
  end

  test "falls back to rack server when rackup server cannot be loaded" do
    original_rackup = Rails.const_get(:Rackup) if Rails.const_defined?(:Rackup, false)
    fallback = Class.new
    rack_had_server = Rack.const_defined?(:Server, false)
    original_rack_server = Rack.const_get(:Server) if rack_had_server
    Rack.send(:remove_const, :Server) if rack_had_server
    Rack.const_set(:Server, fallback)
    Rails.send(:remove_const, :Rackup) if Rails.const_defined?(:Rackup, false)

    with_kernel_require("rackup/server" => LoadError.new("rackup unavailable"), "rack/server" => true) do
      load File.expand_path("../lib/rails/rackup/server.rb", __dir__)
    end

    assert_same fallback, Rails::Rackup::Server
  ensure
    Rails.send(:remove_const, :Rackup) if Rails.const_defined?(:Rackup, false)
    Rails.const_set(:Rackup, original_rackup) if original_rackup
    Rack.send(:remove_const, :Server) if Rack.const_defined?(:Server, false)
    Rack.const_set(:Server, original_rack_server) if rack_had_server
  end

  private
    def with_kernel_require(overrides)
      Kernel.module_eval do
        alias_method :__rackup_server_public_contract_original_require, :require
        define_method(:require) do |path|
          if overrides.key?(path)
            value = overrides[path]
            raise value if value.is_a?(Exception)
            value
          else
            __rackup_server_public_contract_original_require(path)
          end
        end
      end

      yield
    ensure
      Kernel.module_eval do
        remove_method :require
        alias_method :require, :__rackup_server_public_contract_original_require
        remove_method :__rackup_server_public_contract_original_require
      end
    end
end
