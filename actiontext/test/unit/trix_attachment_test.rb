# frozen_string_literal: true

require "test_helper"

class ActionText::TrixAttachmentTest < ActiveSupport::TestCase
  test "builds and reads typecast attributes" do
    trix_attachment = ActionText::TrixAttachment.from_attributes(
      sgid: "123",
      content_type: "image/png",
      filesize: "42",
      width: "640",
      height: "480",
      previewable: "true",
      caption: "Captioned",
      presentation: "gallery"
    )

    assert_match %r{\A<figure data-trix-attachment=}, trix_attachment.to_html
    assert_equal trix_attachment.to_html, trix_attachment.to_s
    assert_same trix_attachment.node, trix_attachment.node
    assert_equal({
      "sgid" => "123",
      "contentType" => "image/png",
      "filesize" => 42,
      "width" => 640,
      "height" => 480,
      "previewable" => true,
      "caption" => "Captioned",
      "presentation" => "gallery"
    }, trix_attachment.attributes)
    assert_same trix_attachment.attributes, trix_attachment.attributes
  end

  test "omits composed attributes payload when empty and tolerates invalid json" do
    trix_attachment = ActionText::TrixAttachment.from_attributes(filename: "report.txt", filesize: "unknown", previewable: "false")

    assert_nil trix_attachment.node["data-trix-attributes"]
    assert_equal "unknown", trix_attachment.attributes["filesize"]
    assert_equal false, trix_attachment.attributes["previewable"]

    invalid = ActionText::TrixAttachment.new(ActionText::HtmlConversion.create_element("figure"))
    invalid.node["data-trix-attachment"] = "{"
    assert_equal({}, invalid.attributes)
  end
end
