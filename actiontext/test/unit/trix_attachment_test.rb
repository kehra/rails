# frozen_string_literal: true

require "test_helper"

class ActionText::TrixAttachmentTest < ActiveSupport::TestCase
  test "from_attributes" do
    attributes = {
      "data-trix-attachment" => {
        "sgid" => "123",
        "contentType" => "text/plain",
        "href" => "http://example.com/",
        "filename" => "example.txt",
        "filesize" => 12345,
        "previewable" => true
      },
      "data-trix-attributes" => {
        "caption" => "hello"
      }
    }

    attachment = attachment(
      sgid: "123",
      content_type: "text/plain",
      href: "http://example.com/",
      filename: "example.txt",
      filesize: "12345",
      previewable: "true",
      caption: "hello"
    )

    assert_attachment_json_attributes(attachment, attributes)
  end

  test "previewable is typecast" do
    assert_attachment_attribute(attachment(previewable: ""), "previewable", false)
    assert_attachment_attribute(attachment(previewable: false), "previewable", false)
    assert_attachment_attribute(attachment(previewable: "false"), "previewable", false)
    assert_attachment_attribute(attachment(previewable: "garbage"), "previewable", false)
    assert_attachment_attribute(attachment(previewable: true), "previewable", true)
    assert_attachment_attribute(attachment(previewable: "true"), "previewable", true)
  end

  test "filesize is typecast when integer-like" do
    assert_attachment_attribute(attachment(filesize: 123), "filesize", 123)
    assert_attachment_attribute(attachment(filesize: "123"), "filesize", 123)
    assert_attachment_attribute(attachment(filesize: "3.5 MB"), "filesize", "3.5 MB")
    assert_attachment_attribute(attachment(filesize: nil), "filesize", nil)
    assert_attachment_attribute(attachment(filesize: ""), "filesize", "")
  end

  test "#attributes strips unmappable attributes" do
    attributes = {
      "sgid" => "123",
      "caption" => "hello"
    }

    attachment = attachment(sgid: "123", caption: "hello", nonexistent: "garbage")
    assert_attachment_attributes(attachment, attributes)
  end

  test "builds and reads html string node and memoized attributes" do
    trix_attachment = attachment(
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
    assert_equal 42, trix_attachment.attributes["filesize"]
    assert_equal 640, trix_attachment.attributes["width"]
    assert_equal 480, trix_attachment.attributes["height"]
    assert_equal true, trix_attachment.attributes["previewable"]
    assert_equal "Captioned", trix_attachment.attributes["caption"]
    assert_equal "gallery", trix_attachment.attributes["presentation"]
    assert_same trix_attachment.attributes, trix_attachment.attributes
  end

  test "omits composed attributes payload when empty and tolerates invalid json" do
    trix_attachment = attachment(filename: "report.txt", filesize: "unknown", previewable: "false")

    assert_nil trix_attachment.node["data-trix-attributes"]
    assert_equal "unknown", trix_attachment.attributes["filesize"]
    assert_equal false, trix_attachment.attributes["previewable"]

    invalid = ActionText::TrixAttachment.new(ActionText::HtmlConversion.create_element("figure"))
    invalid.node["data-trix-attachment"] = "{"
    assert_equal({}, invalid.attributes)
  end

  def assert_attachment_attribute(attachment, name, value)
    if value.nil?
      assert_nil(attachment.attributes[name])
    else
      assert_equal(value, attachment.attributes[name])
    end
  end

  def assert_attachment_attributes(attachment, attributes)
    assert_equal(attributes, attachment.attributes)
  end

  def assert_attachment_json_attributes(attachment, attributes)
    attributes.each do |name, expected|
      actual = JSON.parse(attachment.node[name])
      assert_equal(expected, actual)
    end
  end

  def attachment(**attributes)
    ActionText::TrixAttachment.from_attributes(attributes)
  end
end
