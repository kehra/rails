# frozen_string_literal: true

require "abstract_unit"

class FormTagPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::FormTagHelper

  def url_for(options = {})
    options == false ? false : "/uploads"
  end

  test "checkbox_tag and radio_button_tag reject too many arguments" do
    checkbox_error = assert_raises(ArgumentError) do
      checkbox_tag("accept", "yes", false, {}, :extra)
    end
    assert_match "expected 1..4", checkbox_error.message

    radio_error = assert_raises(ArgumentError) do
      radio_button_tag("color", "red", false, {}, :extra)
    end
    assert_match "expected 2..4", radio_error.message
  end

  test "number_field_tag expands inclusive range into min and max" do
    assert_dom_equal '<input id="quantity" name="quantity" type="number" min="1" max="3" />',
      number_field_tag("quantity", nil, in: 1..3)
    assert_dom_equal '<input id="quantity" name="quantity" type="number" value="2" />',
      number_field_tag("quantity", 2)
  end

  test "form_tag omits action for false url and false action html option" do
    assert_includes form_tag(false), '<form accept-charset="UTF-8" method="post">'
    assert_includes form_tag("/ignored", action: false), '<form accept-charset="UTF-8" method="post">'
  end

  test "remote form_tag handles authenticity token options" do
    output = form_tag("/uploads", remote: true, authenticity_token: true)

    assert_includes output, 'data-remote="true"'
    assert_includes output, '<form action="/uploads"'

    old = self.embed_authenticity_token_in_remote_forms
    self.embed_authenticity_token_in_remote_forms = false
    begin
      output = form_tag("/uploads", remote: true)
      assert_includes output, 'data-remote="true"'
      assert_not_includes output, 'name="authenticity_token"'
    ensure
      self.embed_authenticity_token_in_remote_forms = old
    end
  end

  test "file_field_tag direct upload uses helper url and checksum algorithm" do
    def rails_direct_uploads_url
      "/rails/direct_uploads"
    end

    output = file_field_tag("avatar", direct_upload: true, data_checksum_algorithm: "sha256")

    assert_includes output, 'data-direct-upload-url="/rails/direct_uploads"'
    assert_includes output, 'data-checksum-algorithm="sha256"'
  end

  test "file_field_tag direct upload falls back to main app url" do
    main = Object.new
    def main.rails_direct_uploads_url
      "/main/direct_uploads"
    end
    define_singleton_method(:main_app) { main }
    define_singleton_method(:respond_to?) do |name, include_private = false|
      name == :rails_direct_uploads_url ? false : super(name, include_private)
    end

    output = file_field_tag("avatar", direct_upload: true)

    assert_includes output, 'data-direct-upload-url="/main/direct_uploads"'
  ensure
    singleton_class.remove_method(:main_app) if singleton_methods.include?(:main_app)
    singleton_class.remove_method(:respond_to?) if singleton_methods.include?(:respond_to?)
  end
end
