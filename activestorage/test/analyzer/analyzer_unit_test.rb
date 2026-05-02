# frozen_string_literal: true

require "test_helper"
require "database/setup"
require "active_storage/analyzer/null_analyzer"

class ActiveStorage::AnalyzerUnitTest < ActiveSupport::TestCase
  test "base analyzer defaults and abstract metadata" do
    blob = create_blob
    analyzer = ActiveStorage::Analyzer.new(blob)

    assert_not ActiveStorage::Analyzer.accept?(blob)
    assert ActiveStorage::Analyzer.analyze_later?
    assert_same blob, analyzer.blob
    assert_raises(NotImplementedError) { analyzer.metadata }
  end

  test "null analyzer accepts anything and returns no metadata inline" do
    blob = create_blob
    analyzer = ActiveStorage::Analyzer::NullAnalyzer.new(blob)

    assert ActiveStorage::Analyzer::NullAnalyzer.accept?(blob)
    assert_not ActiveStorage::Analyzer::NullAnalyzer.analyze_later?
    assert_equal({}, analyzer.metadata)
  end
end
