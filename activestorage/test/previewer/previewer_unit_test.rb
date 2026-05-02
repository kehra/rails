# frozen_string_literal: true

require "test_helper"
require "database/setup"
require "active_storage/previewer/mupdf_previewer"
require "active_storage/previewer/poppler_pdf_previewer"
require "active_storage/previewer/video_previewer"

class ActiveStorage::PreviewerUnitTest < ActiveSupport::TestCase
  test "base previewer defaults and abstract preview" do
    blob = create_blob
    previewer = ActiveStorage::Previewer.new(blob)

    assert_not ActiveStorage::Previewer.accept?(blob)
    assert_same blob, previewer.blob
    assert_raises(NotImplementedError) { previewer.preview {} }
    assert_same ActiveStorage.logger, previewer.send(:logger)
  end

  test "mupdf previewer accepts PDF only when mutool exists" do
    pdf = create_blob(content_type: "application/pdf")
    text = create_blob(content_type: "text/plain")

    ActiveStorage::Previewer::MuPDFPreviewer.instance_variable_set(:@mutool_exists, nil)
    ActiveStorage::Previewer::MuPDFPreviewer.stub(:mutool_path, "/bin/false") do
      assert ActiveStorage::Previewer::MuPDFPreviewer.mutool_exists?
      assert ActiveStorage::Previewer::MuPDFPreviewer.mutool_exists?
    end

    ActiveStorage::Previewer::MuPDFPreviewer.stub(:mutool_exists?, true) do
      assert ActiveStorage::Previewer::MuPDFPreviewer.accept?(pdf)
      assert_not ActiveStorage::Previewer::MuPDFPreviewer.accept?(text)
      assert ActiveStorage::Previewer::MuPDFPreviewer.pdf?("application/pdf")
      assert_equal "mutool", ActiveStorage::Previewer::MuPDFPreviewer.mutool_path
    end
  ensure
    ActiveStorage::Previewer::MuPDFPreviewer.instance_variable_set(:@mutool_exists, nil)
  end

  test "poppler previewer accepts PDF only when pdftoppm exists" do
    pdf = create_blob(content_type: "application/pdf")
    text = create_blob(content_type: "text/plain")

    ActiveStorage::Previewer::PopplerPDFPreviewer.instance_variable_set(:@pdftoppm_exists, nil)
    ActiveStorage::Previewer::PopplerPDFPreviewer.stub(:system, true) do
      ActiveStorage::Previewer::PopplerPDFPreviewer.stub(:pdftoppm_path, "pdftoppm") do
        assert ActiveStorage::Previewer::PopplerPDFPreviewer.pdftoppm_exists?
        assert ActiveStorage::Previewer::PopplerPDFPreviewer.pdftoppm_exists?
      end
    end

    ActiveStorage::Previewer::PopplerPDFPreviewer.stub(:pdftoppm_exists?, true) do
      assert ActiveStorage::Previewer::PopplerPDFPreviewer.accept?(pdf)
      assert_not ActiveStorage::Previewer::PopplerPDFPreviewer.accept?(text)
      assert ActiveStorage::Previewer::PopplerPDFPreviewer.pdf?("application/pdf")
      assert_equal "pdftoppm", ActiveStorage::Previewer::PopplerPDFPreviewer.pdftoppm_path
    end
  ensure
    ActiveStorage::Previewer::PopplerPDFPreviewer.instance_variable_set(:@pdftoppm_exists, nil)
  end

  test "video previewer accepts videos only when ffmpeg exists" do
    video = create_blob(content_type: "video/mp4")
    text = create_blob(content_type: "text/plain")

    ActiveStorage::Previewer::VideoPreviewer.instance_variable_set(:@ffmpeg_exists, nil)
    ActiveStorage::Previewer::VideoPreviewer.stub(:system, true) do
      ActiveStorage::Previewer::VideoPreviewer.stub(:ffmpeg_path, "ffmpeg") do
        assert ActiveStorage::Previewer::VideoPreviewer.ffmpeg_exists?
        assert ActiveStorage::Previewer::VideoPreviewer.ffmpeg_exists?
      end
    end

    ActiveStorage::Previewer::VideoPreviewer.stub(:ffmpeg_exists?, true) do
      assert ActiveStorage::Previewer::VideoPreviewer.accept?(video)
      assert_not ActiveStorage::Previewer::VideoPreviewer.accept?(text)
      assert_equal "ffmpeg", ActiveStorage::Previewer::VideoPreviewer.ffmpeg_path
    end
  ensure
    ActiveStorage::Previewer::VideoPreviewer.instance_variable_set(:@ffmpeg_exists, nil)
  end
end
