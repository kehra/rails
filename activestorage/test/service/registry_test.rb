# frozen_string_literal: true

require "test_helper"

class ActiveStorage::Service::RegistryTest < ActiveSupport::TestCase
  test "fetch builds and caches configured services" do
    registry = ActiveStorage::Service::Registry.new(local: { service: "Disk", root: "/tmp/active_storage_registry_test" })

    service = registry.fetch(:local)

    assert_instance_of ActiveStorage::Service::DiskService, service
    assert_same service, registry.fetch("local")
  end

  test "fetch yields missing service names when block is given" do
    registry = ActiveStorage::Service::Registry.new({})

    assert_equal :missing, registry.fetch(:missing) { |key| key }
  end

  test "fetch raises for missing services without a block" do
    registry = ActiveStorage::Service::Registry.new(local: { service: "Disk", root: "/tmp/active_storage_registry_test" })

    error = assert_raises(KeyError) do
      registry.fetch(:missing)
    end

    assert_match(/Missing configuration for the missing Active Storage service/, error.message)
  end

  test "inspect attributes" do
    registry = ActiveStorage::Service::Registry.new({})
    assert_match(/#<ActiveStorage::Service::Registry>/, registry.inspect)
  end

  test "inspect attributes with config" do
    config = {
      local: { service: "Disk", root: "/tmp/active_storage_registry_test" },
      tmp: { service: "Disk", root: "/tmp/active_storage_registry_test_tmp" },
    }

    registry = ActiveStorage::Service::Registry.new(config)
    assert_match(/#<ActiveStorage::Service::Registry configurations=\[:local, :tmp\]>/, registry.inspect)
  end
end
