# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/testing/assertions"

class ActionDispatchAssertionsTest < ActiveSupport::TestCase
  include ActionDispatch::Assertions

  test "html_document parses HTML when response has no media type" do
    @response = Struct.new(:media_type, :body).new(nil, "<main>Hello</main>")

    assert_kind_of Nokogiri::HTML::Document, html_document
    assert_same html_document, html_document
  end
end
