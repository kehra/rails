# frozen_string_literal: true

require "cases/helper"

class SqlTypesTest < ActiveRecord::AbstractMysqlTestCase
  def test_binary_types
    assert_equal "varbinary(64)", type_to_sql(:binary, 64)
    assert_equal "varbinary(4095)", type_to_sql(:binary, 4095)
    assert_equal "blob", type_to_sql(:binary, 4096)
    assert_equal "blob", type_to_sql(:binary)
  end

  def test_native_database_types_can_be_extended
    native_database_types = ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::NATIVE_DATABASE_TYPES
    native_database_types[:vector] = { name: "vector" }

    assert_equal({ name: "vector" }, native_database_types[:vector])
  ensure
    native_database_types.delete(:vector) if native_database_types
  end

  def type_to_sql(type, limit = nil)
    ActiveRecord::Base.lease_connection.type_to_sql(type, limit: limit)
  end
end
