# frozen_string_literal: true

require "cases/helper"

class ArelSqlTest < ActiveSupport::TestCase
  test "returns existing sql literal unchanged" do
    literal = Arel::Nodes::SqlLiteral.new("LOWER(name)", retryable: true)

    assert_same literal, Arel.sql(literal)
  end

  test "wraps raw sql strings in sql literal" do
    literal = Arel.sql("LOWER(name)", retryable: true)

    assert_instance_of Arel::Nodes::SqlLiteral, literal
    assert_equal "LOWER(name)", literal
    assert_predicate literal, :retryable
  end

  test "wraps sql with positional binds in bound sql literal" do
    literal = Arel.sql("name = ?", "David")

    assert_instance_of Arel::Nodes::BoundSqlLiteral, literal
    assert_equal "name = ?", literal.sql_with_placeholders
    assert_equal ["David"], literal.positional_binds
    assert_nil literal.named_binds
  end

  test "wraps sql with named binds in bound sql literal" do
    literal = Arel.sql("name = :name", name: "David")

    assert_instance_of Arel::Nodes::BoundSqlLiteral, literal
    assert_equal "name = :name", literal.sql_with_placeholders
    assert_nil literal.positional_binds
    assert_equal({ name: "David" }, literal.named_binds)
  end
end
