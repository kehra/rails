# frozen_string_literal: true

require "test_helper"

class ActionText::ModelTest < ActiveSupport::TestCase
  include QueryHelpers

  test "html conversion" do
    message = Message.new(subject: "Greetings", content: "<h1>Hello world</h1>")
    assert_equal %Q(<div class="trix-content">\n  <h1>Hello world</h1>\n</div>\n), "#{message.content}"
  end

  test "plain text conversion" do
    message = Message.new(subject: "Greetings", content: "<h1>Hello world</h1>")
    assert_equal "Hello world", message.content.to_plain_text
  end

  test "rich text editor html conversion" do
    rich_text = ActionText::RichText.new(body: "<p><strong>Hello</strong> world</p>")
    assert_equal "<p><strong>Hello</strong> world</p>", rich_text.to_editor_html

    assert_nil ActionText::RichText.new(body: nil).to_editor_html
  end

  test "rich text trix html delegates to editor html" do
    rich_text = ActionText::RichText.new(body: "<p>Hello world</p>")

    assert_deprecated(ActionText.deprecator) do
      assert_equal rich_text.to_editor_html, rich_text.to_trix_html
    end
  end

  test "rich text class editor accessors" do
    original_editor = ActionText::RichText.editor
    original_editors = ActionText::RichText.editors
    editor = Object.new
    editors = { custom: editor }

    ActionText::RichText.editor = editor
    ActionText::RichText.editors = editors

    assert_same editor, ActionText::RichText.editor
    assert_same editors, ActionText::RichText.editors
  ensure
    ActionText::RichText.editor = original_editor
    ActionText::RichText.editors = original_editors
  end

  test "rich text association contracts" do
    blob = create_file_blob(filename: "racecar.jpg", content_type: "image/jpeg")
    message = Message.create!(subject: "Greetings", content: ActionText::Content.new("Hello world").append_attachables(blob))

    assert_same message, message.content.record
    assert_equal [blob], message.content.embeds.map(&:blob)
  end

  test "without content" do
    assert_difference("ActionText::RichText.count" => 0) do
      message = Message.create!(subject: "Greetings")
      assert_equal true, message.content.nil?
      assert_predicate message.content, :blank?
      assert_predicate message.content, :empty?
      assert_not message.content?
      assert_not message.content.present?
    end
  end

  test "with blank content" do
    assert_difference("ActionText::RichText.count" => 1) do
      message = Message.create!(subject: "Greetings", content: "")
      assert_not message.content.nil?
      assert_predicate message.content, :blank?
      assert_predicate message.content, :empty?
      assert_not message.content?
      assert_not message.content.present?
    end
  end

  test "embed extraction" do
    blob = create_file_blob(filename: "racecar.jpg", content_type: "image/jpeg")
    message = Message.create!(subject: "Greetings", content: ActionText::Content.new("Hello world").append_attachables(blob))
    assert_equal "racecar.jpg", message.content.embeds.first.filename.to_s
  end

  test "embed extraction only extracts file attachments" do
    remote_image_html = '<action-text-attachment content-type="image" url="http://example.com/cat.jpg"></action-text-attachment>'
    blob = create_file_blob(filename: "racecar.jpg", content_type: "image/jpeg")
    content = ActionText::Content.new(remote_image_html).append_attachables(blob)
    message = Message.create!(subject: "Greetings", content: content)
    assert_equal [ActionText::Attachables::RemoteImage, ActiveStorage::Blob], message.content.body.attachables.map(&:class)
    assert_equal [ActiveStorage::Attachment], message.content.embeds.map(&:class)
  end

  test "embed extraction deduplicates file attachments" do
    blob = create_file_blob(filename: "racecar.jpg", content_type: "image/jpeg")
    content = ActionText::Content.new("Hello world").append_attachables([ blob, blob ])

    assert_nothing_raised do
      Message.create!(subject: "Greetings", content: content)
    end
  end

  test "embed extraction occurs before validation" do
    blob = create_file_blob(filename: "racecar.jpg", content_type: "image/jpeg")
    content = ActionText::Content.new.append_attachables(blob)
    message = Message.build(subject: "Greetings", content: content)

    assert_changes -> { message.content.embeds.empty? }, from: true, to: false do
      message.content.validate
    end

    embeds = message.content.embeds
    assert_kind_of ActiveStorage::Attached::Many, embeds
    assert_kind_of ActiveStorage::Attachment, embeds.first
    assert_equal blob, embeds.first.blob
  end

  test "saving content" do
    message = Message.create!(subject: "Greetings", content: "<h1>Hello world</h1>")
    assert_equal "Hello world", message.content.to_plain_text
  end

  test "duplicating content" do
    message = Message.create!(subject: "Greetings", content: "<b>Hello!</b>")
    other_message = Message.create!(subject: "Greetings", content: message.content)

    assert_equal message.content.body.to_html, other_message.content.body.to_html
  end

  test "saving body" do
    message = Message.create(subject: "Greetings", body: "<h1>Hello world</h1>")
    assert_equal "Hello world", message.body.to_plain_text
  end

  test "saving content via nested attributes" do
    message = Message.create! subject: "Greetings", content: "<h1>Hello world</h1>",
      review_attributes: { author_name: "Marcia", content: "Nice work!" }
    assert_equal "Nice work!", message.review.content.to_plain_text
  end

  test "updating content via nested attributes" do
    message = Message.create! subject: "Greetings", content: "<h1>Hello world</h1>",
      review_attributes: { author_name: "Marcia", content: "Nice work!" }

    message.update! review_attributes: { id: message.review.id, content: "Great work!" }
    assert_equal "Great work!", message.review.reload.content.to_plain_text
  end

  test "building content lazily on existing record" do
    message = Message.create!(subject: "Greetings")

    assert_no_difference -> { ActionText::RichText.count } do
      assert_kind_of ActionText::RichText, message.content
    end
  end

  test "rich text association names" do
    assert_equal [ :rich_text_content, :rich_text_body ], Message.rich_text_association_names
  end

  test "eager loading" do
    Message.create!(subject: "Subject", content: "<h1>Content</h1>")

    message = assert_queries_count(2) { Message.with_rich_text_content.last }
    assert_no_queries do
      assert_equal "Content", message.content.to_plain_text
    end
  end

  test "eager loading with embeds" do
    blob = create_file_blob(filename: "racecar.jpg", content_type: "image/jpeg")
    Message.create!(subject: "Subject", content: ActionText::Content.new("Content").append_attachables(blob))

    message = Message.with_rich_text_content_and_embeds.last

    assert_predicate message.association(:rich_text_content), :loaded?
    assert_predicate message.content.embeds.proxy_association, :loaded?
    assert_predicate message.content.embeds.first.association(:blob), :loaded?
  end

  test "eager loading all rich text" do
    2.times do
      Message.create!(subject: "Subject", content: "<h1>Content</h1>", body: "<h2>Body</h2>")
    end

    message = assert_queries_count(3) do
      # 3 queries:
      # messages x 1
      # action texts (content) x 1
      # action texts (body) x 1
      Message.with_all_rich_text.to_a.last
    end

    assert_no_queries do
      assert_equal "Content", message.content.to_plain_text
      assert_equal "Body", message.body.to_plain_text
    end
  end

  test "with blank content and store_if_blank: false" do
    assert_difference("ActionText::RichText.count" => 0) do
      message = MessageWithoutBlanks.create!(subject: "Greetings", content: "")
      assert_equal true, message.content.nil?
      assert_predicate message.content, :blank?
      assert_predicate message.content, :empty?
      assert_not message.content?
      assert_not message.content.present?
    end
  end

  test "if allowing blanks, updates rich text record on edit" do
    message = Message.create!(subject: "Greetings", content: "content")
    assert_difference("ActionText::RichText.count" => 0) do
      message.update(content: "")
    end
  end

  test "if disallowing blanks, deletes rich text record on edit" do
    message = MessageWithoutBlanks.create!(subject: "Greetings", content: "content")
    assert_difference("ActionText::RichText.count" => -1) do
      message.update(content: "")
    end
  end

  test "if disallowing blanks, can still validate presence" do
    message1 = MessageWithoutBlanksWithContentValidation.new(subject: "Greetings", content: "")
    assert_not_predicate message1, :valid?
    message1.content = "content"
    assert_predicate message1, :valid?

    message2 = MessageWithoutBlanksWithContentValidation.new(subject: "Greetings", content: "content")
    assert_predicate message2, :valid?
    message2.content = ""
    assert_not_predicate message2, :valid?
  end
end
