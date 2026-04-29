# frozen_string_literal: true

require "test_helper"

class ActionText::AttachableTest < ActiveSupport::TestCase
  test "find attachables from sgids" do
    attachable = ActiveStorage::Blob.create_after_unfurling!(io: StringIO.new("test"), filename: "test.txt", key: "sgid-test")

    assert_equal attachable, ActionText::Attachable.from_attachable_sgid(attachable.attachable_sgid)
    assert_equal [attachable], ActionText::Attachable.from_attachable_sgid([attachable.attachable_sgid])
    assert_equal attachable, ActiveStorage::Blob.from_attachable_sgid(attachable.attachable_sgid)
    assert_raises(ActiveRecord::RecordNotFound) { ActionText::Attachable.from_attachable_sgid("missing") }
  end

  test "find attachable from attachment nodes" do
    attachable = ActiveStorage::Blob.create_after_unfurling!(io: StringIO.new("test"), filename: "test.txt", key: "node-test")

    assert_equal attachable, ActionText::Attachable.from_node(attachment_node(%(sgid="#{attachable.attachable_sgid}")))
    assert_instance_of ActionText::Attachables::ContentAttachment, ActionText::Attachable.from_node(attachment_node(%(content-type="text/html" content="<strong>Hello</strong>")))
    assert_instance_of ActionText::Attachables::RemoteImage, ActionText::Attachable.from_node(attachment_node(%(url="https://example.com/image.jpg" content-type="image/jpeg")))
    assert_instance_of ActionText::Attachables::MissingAttachable, ActionText::Attachable.from_node(attachment_node(%(sgid="missing")))
  end

  test "default missing attachable partial path" do
    assert_equal ActionText::Attachables::MissingAttachable::DEFAULT_PARTIAL_PATH, ActiveStorage::Blob.to_missing_attachable_partial_path
  end

  test "missing attachable representations and partial paths" do
    person = Person.create!(name: "Javan")
    missing_person = ActionText::Attachables::MissingAttachable.new(person.attachable_sgid)
    missing_unknown = ActionText::Attachables::MissingAttachable.new("missing")

    assert_equal "people/missing_attachable", missing_person.to_partial_path
    assert_equal Person, missing_person.model
    assert_equal ActionText::Attachables::MissingAttachable::DEFAULT_PARTIAL_PATH, missing_unknown.to_partial_path
    assert_nil missing_unknown.model
    assert_equal "☒", missing_unknown.attachable_plain_text_representation
    assert_equal "☒", missing_unknown.attachable_markdown_representation
  end

  test "remote image attachable from node and representations" do
    image = ActionText::Attachables::RemoteImage.from_node(attachment_node(%(url="https://example.com/image.jpg" content-type="image/jpeg" width="640" height="480")))

    assert_equal "https://example.com/image.jpg", image.url
    assert_equal "image/jpeg", image.content_type
    assert_equal "640", image.width
    assert_equal "480", image.height
    assert_equal "[Caption]", image.attachable_plain_text_representation("Caption")
    assert_equal "[Image]", image.attachable_plain_text_representation(nil)
    assert_equal "![Caption](https://example.com/image.jpg)", image.attachable_markdown_representation("Caption")
    assert_equal "![Image](https://example.com/image.jpg)", image.attachable_markdown_representation(nil)
    assert_equal "action_text/attachables/remote_image", image.to_partial_path
    assert_nil ActionText::Attachables::RemoteImage.from_node(attachment_node(%(url="/image.jpg" content-type="image/jpeg")))
    assert_nil ActionText::Attachables::RemoteImage.from_node(attachment_node(%(url="https://example.com/file.txt" content-type="text/plain")))
  end

  test "attachable metadata helpers and rich text attributes" do
    attachable = ActiveStorage::Blob.create_after_unfurling!(
      io: StringIO.new("test"),
      filename: "test.txt",
      key: "attribute-test",
      content_type: "text/plain",
      metadata: { width: 640, height: 480 }
    )

    assert_equal "text/plain", attachable.attachable_content_type
    assert_equal "test.txt", attachable.attachable_filename
    assert_equal 4, attachable.attachable_filesize
    assert_equal({ "width" => 640, "height" => 480, "identified" => true }, attachable.attachable_metadata)
    assert_not attachable.previewable_attachable?

    custom_attachable = Class.new do
      include ActionText::Attachable

      def to_partial_path
        "custom/attachable"
      end
    end.new
    assert_equal "application/octet-stream", custom_attachable.attachable_content_type
    assert_nil custom_attachable.attachable_filename
    assert_nil custom_attachable.attachable_filesize
    assert_equal({}, custom_attachable.attachable_metadata)
    assert_not custom_attachable.previewable_attachable?
    assert_equal "custom/attachable", custom_attachable.to_attachable_partial_path
    assert_equal "custom/attachable", custom_attachable.to_editor_content_attachment_partial_path
    assert_deprecated(ActionText.deprecator) do
      assert_equal custom_attachable.to_editor_content_attachment_partial_path, custom_attachable.to_trix_content_attachment_partial_path
    end

    attributes = attachable.to_rich_text_attributes(caption: "Caption")
    assert_equal "Caption", attributes[:caption]
    assert_equal attachable.attachable_sgid, attributes[:sgid]
    assert_equal "text/plain", attributes[:content_type]
    assert_equal "test.txt", attributes[:filename]
    assert_equal 4, attributes[:filesize]
    assert_equal 640, attributes[:width]
    assert_equal 480, attributes[:height]
    assert_not attributes.key?(:previewable)

    attachable.stub(:previewable_attachable?, true) do
      assert_equal true, attachable.to_rich_text_attributes[:previewable]
    end
  end

  test "as_json is a hash when the attachable is persisted" do
    freeze_time do
      attachable = ActiveStorage::Blob.create_after_unfurling!(io: StringIO.new("test"), filename: "test.txt", key: 123)
      attributes = {
        id: attachable.id,
        key: "123",
        filename: "test.txt",
        content_type: "text/plain",
        metadata: { identified: true },
        service_name: "test",
        byte_size: 4,
        checksum: "CY9rzUYh03PK3k6DJie09g==",
        created_at: Time.zone.now.as_json,
        attachable_sgid: attachable.attachable_sgid
      }.deep_stringify_keys

      assert_equal attributes, attachable.as_json
    end
  end

  test "as_json is a hash when the attachable is a new record" do
    attachable = ActiveStorage::Blob.build_after_unfurling(io: StringIO.new("test"), filename: "test.txt", key: 123)
    attributes = {
      id: nil,
      key: "123",
      filename: "test.txt",
      content_type: "text/plain",
      metadata: { identified: true },
      service_name: "test",
      byte_size: 4,
      checksum: "CY9rzUYh03PK3k6DJie09g==",
      created_at: nil,
      attachable_sgid: nil
    }.deep_stringify_keys

    assert_equal attributes, attachable.as_json
  end

  test "attachable_sgid is included in as_json when only option is nil or includes attachable_sgid" do
    attachable = ActiveStorage::Blob.create_after_unfurling!(io: StringIO.new("test"), filename: "test.txt", key: 123)

    assert_equal({ "id" => attachable.id }, attachable.as_json(only: :id))
    assert_equal({ "id" => attachable.id }, attachable.as_json(only: [:id]))
    assert_equal(attachable.as_json.except("attachable_sgid"), attachable.as_json(except: :attachable_sgid))
    assert_equal(attachable.as_json.except("attachable_sgid"), attachable.as_json(except: [:attachable_sgid]))
  end

  test "read_attribute_for_serialization returns the attribute" do
    attachable = ActiveStorage::Blob.create_after_unfurling!(io: StringIO.new("test"), filename: "test.txt", key: 123)

    assert_equal(attachable.key, attachable.read_attribute_for_serialization(:key))
  end

  private
    def attachment_node(attributes)
      ActionText::Fragment.wrap(%(<action-text-attachment #{attributes}></action-text-attachment>)).find_all(ActionText::Attachment.tag_name).first
    end
end
