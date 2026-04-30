# frozen_string_literal: true

require "cases/helper"
require "models/author"
require "models/post"

class SQLite3ExplainTest < ActiveRecord::SQLite3TestCase
  fixtures :authors, :author_addresses

  def test_sqlite_explain_formats_query_plan_rows
    connection = ActiveRecord::Base.lease_connection
    output = connection.explain("SELECT * FROM authors WHERE id = 1")

    assert_match(/SEARCH|SCAN/, output)
    assert_match(/authors/, output)
    assert output.end_with?("\n")
  end

  def test_sqlite_explain_pretty_printer_joins_rows_like_shell_output
    output = ActiveRecord::ConnectionAdapters::SQLite3::ExplainPrettyPrinter.new.pp([
      [0, 0, 0, "SCAN TABLE authors"],
      [0, 1, 1, "SEARCH TABLE posts USING INDEX index_posts_on_author_id"],
    ])

    assert_equal <<~OUTPUT, output
      0|0|0|SCAN TABLE authors
      0|1|1|SEARCH TABLE posts USING INDEX index_posts_on_author_id
    OUTPUT
  end

  def test_sqlite_high_precision_current_timestamp_uses_strftime
    timestamp_sql = ActiveRecord::Base.lease_connection.high_precision_current_timestamp

    assert_equal "STRFTIME('%Y-%m-%d %H:%M:%f', 'NOW')", timestamp_sql.to_s
    assert timestamp_sql.retryable
  end

  def test_explain_for_one_query
    explain = Author.where(id: 1).explain.inspect
    assert_match %r(EXPLAIN for: SELECT "authors"\.\* FROM "authors" WHERE "authors"\."id" = (?:\? \[\["id", 1\]\]|1)), explain
    assert_match(/(SEARCH )?(TABLE )?authors USING (INTEGER )?PRIMARY KEY/, explain)
  end

  def test_explain_with_eager_loading
    explain = Author.where(id: 1).includes(:posts).explain.inspect
    assert_match %r(EXPLAIN for: SELECT "authors"\.\* FROM "authors" WHERE "authors"\."id" = (?:\? \[\["id", 1\]\]|1)), explain
    assert_match(/(SEARCH )?(TABLE )?authors USING (INTEGER )?PRIMARY KEY/, explain)
    assert_match %r(EXPLAIN for: SELECT "posts"\.\* FROM "posts" WHERE "posts"\."author_id" = (?:\? \[\["author_id", 1\]\]|1)), explain
    assert_match(/(SEARCH |(SCAN )?(TABLE ))posts/, explain)
  end
end
