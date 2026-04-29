# frozen_string_literal: true

require "test_helper"

class ActionText::AttachmentGalleryTest < ActiveSupport::TestCase
  GALLERY_ATTACHMENTS = <<~HTML.squish
    <action-text-attachment sgid="1" presentation="gallery"></action-text-attachment>
    <action-text-attachment sgid="2" presentation="gallery"></action-text-attachment>
  HTML

  test "selectors target adjacent gallery attachments" do
    assert_equal "action-text-attachment[presentation=gallery]", ActionText::AttachmentGallery.attachment_selector
    assert_equal "div:has(action-text-attachment[presentation=gallery] + action-text-attachment[presentation=gallery])", ActionText::AttachmentGallery.selector
  end

  test "find attachment gallery nodes ignores non-gallery children" do
    html = <<~HTML
      <div id="gallery">
        #{GALLERY_ATTACHMENTS}
      </div>
      <div id="not-gallery">
        <action-text-attachment sgid="1" presentation="gallery"></action-text-attachment>
        <span>caption</span>
        <action-text-attachment sgid="2" presentation="gallery"></action-text-attachment>
      </div>
    HTML

    nodes = ActionText::AttachmentGallery.find_attachment_gallery_nodes(html)

    assert_equal ["gallery"], nodes.map { |node| node["id"] }
  end

  test "canonicalizes and replaces attachment gallery nodes" do
    html = %(<div class="attachment-gallery">#{GALLERY_ATTACHMENTS}</div>)

    canonical = ActionText::AttachmentGallery.fragment_by_canonicalizing_attachment_galleries(html)
    replaced = ActionText::AttachmentGallery.fragment_by_replacing_attachment_gallery_nodes(html) do |node|
      %(<section data-count="#{node.css(ActionText::AttachmentGallery.attachment_selector).size}">#{node.inner_html}</section>)
    end

    assert_equal %(<div>#{GALLERY_ATTACHMENTS}</div>), canonical.to_html
    assert_equal %(<section data-count="2">#{GALLERY_ATTACHMENTS}</section>), replaced.to_html
  end

  test "from node exposes node attachments size and inspect" do
    node = ActionText::AttachmentGallery.find_attachment_gallery_nodes(%(<div>#{GALLERY_ATTACHMENTS}</div>)).first
    gallery = ActionText::AttachmentGallery.from_node(node)

    assert_same node, gallery.node
    assert_equal 2, gallery.size
    assert_equal 2, gallery.attachments.size
    assert_same gallery.attachments, gallery.attachments
    assert_equal "#<ActionText::AttachmentGallery size=2>", gallery.inspect
  end
end
