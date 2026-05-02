# frozen_string_literal: true

require "test_helper"
require "database/setup"

require "active_storage/analyzer/video_analyzer"

class ActiveStorage::Analyzer::VideoAnalyzerTest < ActiveSupport::TestCase
  test "accepts video blobs" do
    assert ActiveStorage::Analyzer::VideoAnalyzer.accept?(create_blob(content_type: "video/mp4"))
    assert_not ActiveStorage::Analyzer::VideoAnalyzer.accept?(create_blob(content_type: "text/plain"))
  end

  test "analyzing a video" do
    blob = create_file_blob(filename: "video.mp4", content_type: "video/mp4")
    metadata = extract_metadata_from(blob)

    assert_equal 640, metadata[:width]
    assert_equal 480, metadata[:height]
    assert_equal [4, 3], metadata[:display_aspect_ratio]
    assert_equal 5.166648, metadata[:duration]
    assert metadata[:audio]
    assert metadata[:video]
    assert_not_includes metadata, :angle
  end

  test "analyzing a rotated video" do
    blob = create_file_blob(filename: "rotated_video.mp4", content_type: "video/mp4")
    metadata = extract_metadata_from(blob)

    assert_equal 480, metadata[:width]
    assert_equal 640, metadata[:height]
    assert_equal [4, 3], metadata[:display_aspect_ratio]
    assert_includes [90, -90], metadata[:angle]
  end

  test "analyzing a rotated HDR video" do
    blob = create_file_blob(filename: "rotated_hdr_video.mov", content_type: "video/quicktime")
    metadata = extract_metadata_from(blob)

    assert_equal 1080.0, metadata[:width]
    assert_equal 1920.0, metadata[:height]
    assert_includes [90, -90], metadata[:angle]
  end

  test "analyzing a video with rectangular samples" do
    blob = create_file_blob(filename: "video_with_rectangular_samples.mp4", content_type: "video/mp4")
    metadata = extract_metadata_from(blob)

    assert_equal 1280, metadata[:width]
    assert_equal 720, metadata[:height]
    assert_equal [16, 9], metadata[:display_aspect_ratio]
  end

  test "analyzing a video with an undefined display aspect ratio" do
    blob = create_file_blob(filename: "video_with_undefined_display_aspect_ratio.mp4", content_type: "video/mp4")
    metadata = extract_metadata_from(blob)

    assert_equal 640, metadata[:width]
    assert_equal 480, metadata[:height]
    assert_nil metadata[:display_aspect_ratio]
  end

  test "analyzing a video with a container-specified duration" do
    blob = create_file_blob(filename: "video.webm", content_type: "video/webm")
    metadata = extract_metadata_from(blob)

    assert_equal 640, metadata[:width]
    assert_equal 480, metadata[:height]
    assert_equal 5.229000, metadata[:duration]
    assert metadata[:audio]
    assert metadata[:video]
  end

  test "analyzing a video without a video stream" do
    blob = create_file_blob(filename: "video_without_video_stream.mp4", content_type: "video/mp4")
    metadata = extract_metadata_from(blob)

    assert_not_includes metadata, :width
    assert_not_includes metadata, :height
    assert_includes 1.000000..1.022000, metadata[:duration]
    assert_not metadata[:video]
    assert metadata[:audio]
  end

  test "analyzing a video without an audio stream" do
    blob = create_file_blob(filename: "video_without_audio_stream.mp4", content_type: "video/mp4")
    metadata = extract_metadata_from(blob)

    assert metadata[:video]
    assert_not metadata[:audio]
  end

  test "instrumenting analysis" do
    blob = create_file_blob(filename: "video.mp4", content_type: "video/mp4")

    assert_notifications_count("analyze.active_storage", 1) do
      assert_notification("analyze.active_storage", analyzer: "ffprobe") do
        blob.analyze
      end
    end
  end

  test "uses display matrix angle and handles missing ffprobe" do
    blob = create_blob(content_type: "video/mp4")
    analyzer = ActiveStorage::Analyzer::VideoAnalyzer.new(blob)
    analyzer.instance_variable_set(:@probe, {
      "streams" => [
        { "codec_type" => "video", "width" => "10", "height" => "20", "side_data_list" => [ { "side_data_type" => "Display Matrix", "rotation" => "270" } ], "display_aspect_ratio" => "0:1" }
      ]
    })

    metadata = analyzer.metadata

    assert_equal 20, metadata[:width]
    assert_equal 10, metadata[:height]
    assert_equal 270, metadata[:angle]
    assert_nil metadata[:display_aspect_ratio]
    assert_not metadata[:audio]
    assert metadata[:video]

    output = StringIO.new
    logger = ActiveSupport::Logger.new(output)
    ActiveStorage.with(logger: logger) do
      analyzer.stub(:ffprobe_path, "missing-ffprobe") do
        assert_equal({}, analyzer.send(:probe_from, Struct.new(:path).new("/tmp/video")))
      end
    end
    assert_includes output.string, "Skipping video analysis because ffprobe isn't installed"
  end

  test "uses rotate tag before display matrix angle" do
    blob = create_blob(content_type: "video/mp4")
    analyzer = ActiveStorage::Analyzer::VideoAnalyzer.new(blob)
    analyzer.instance_variable_set(:@probe, {
      "streams" => [
        { "codec_type" => "video", "width" => "10", "height" => "20", "tags" => { "rotate" => "90" }, "side_data_list" => [ { "side_data_type" => "Display Matrix", "rotation" => "270" } ] }
      ]
    })

    metadata = analyzer.metadata

    assert_equal 90, metadata[:angle]
    assert_equal 20, metadata[:width]
    assert_equal 10, metadata[:height]
  end
end
