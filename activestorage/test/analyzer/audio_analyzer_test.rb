# frozen_string_literal: true

require "test_helper"
require "database/setup"

require "active_storage/analyzer/audio_analyzer"

class ActiveStorage::Analyzer::AudioAnalyzerTest < ActiveSupport::TestCase
  test "accepts audio blobs" do
    assert ActiveStorage::Analyzer::AudioAnalyzer.accept?(create_blob(content_type: "audio/mp3"))
    assert_not ActiveStorage::Analyzer::AudioAnalyzer.accept?(create_blob(content_type: "text/plain"))
  end

  test "analyzing an audio" do
    blob = create_file_blob(filename: "audio.mp3", content_type: "audio/mp3")
    metadata = extract_metadata_from(blob)

    assert (0.863379..0.914286).include?(metadata[:duration])

    assert_equal 128000, metadata[:bit_rate]
    assert_equal 44100, metadata[:sample_rate]
    assert_not_nil metadata[:tags]
    assert_equal "Lavc57.64", metadata[:tags][:encoder]
  end

  test "instrumenting analysis" do
    blob = create_file_blob(filename: "audio.mp3", content_type: "audio/mp3")

    assert_notifications_count("analyze.active_storage", 1) do
      assert_notification("analyze.active_storage", analyzer: "ffprobe") do
        blob.analyze
      end
    end
  end

  test "omits missing stream metadata and logs when ffprobe is unavailable" do
    blob = create_blob(content_type: "audio/mp3")
    analyzer = ActiveStorage::Analyzer::AudioAnalyzer.new(blob)
    analyzer.instance_variable_set(:@probe, { "streams" => [ { "codec_type" => "audio" } ] })

    assert_equal({}, analyzer.metadata)

    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    ActiveStorage.with(logger: logger) do
      analyzer.stub(:ffprobe_path, "missing-ffprobe") do
        assert_equal({}, analyzer.send(:probe_from, Struct.new(:path).new("/tmp/audio")))
      end
    end
    assert_includes output.string, "Skipping audio analysis because ffprobe isn't installed"
  end
end
