# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/html_safe_translation"
require "active_support/core_ext/string/output_safety"
require "erb"
require "i18n"
require "set"

class HtmlSafeTranslationTest < ActiveSupport::TestCase
  setup do
    @old_backend = I18n.backend
    @old_exception_handler = I18n.exception_handler
    I18n.backend = I18n::Backend::Simple.new
    I18n.backend.store_translations(:en, {
      hello: "Hello %{name}",
      hello_html: "Hello %{name}",
      items_html: {
        one: "%{count} <item>",
        other: "%{count} <items>"
      },
      list_html: ["<strong>%{name}</strong>", 1]
    })
    I18n.locale = :en
  end

  teardown do
    I18n.backend = @old_backend
    I18n.exception_handler = @old_exception_handler
  end

  test "translate escapes interpolation values and marks html keys safe" do
    translation = ActiveSupport::HtmlSafeTranslation.translate(:hello_html, name: "<David>")

    assert_equal "Hello &lt;David&gt;", translation
    assert_predicate translation, :html_safe?
  end

  test "translate leaves non html keys and reserved options to i18n" do
    translation = ActiveSupport::HtmlSafeTranslation.translate(:hello, name: "<David>", locale: :en)

    assert_equal "Hello <David>", translation
    assert_not_predicate translation, :html_safe?
  end

  test "translate does not escape numeric count option" do
    translation = ActiveSupport::HtmlSafeTranslation.translate(:items_html, count: 1)

    assert_equal "1 <item>", translation
    assert_predicate translation, :html_safe?
  end

  test "translate escapes non numeric count option" do
    translation = ActiveSupport::HtmlSafeTranslation.translate(:hello_html, count: "<count>", name: "David")

    assert_equal "Hello David", translation
  end

  test "translate returns i18n exception result without marking it safe" do
    I18n.exception_handler = ->(*) { "<missing>" }

    translation = ActiveSupport::HtmlSafeTranslation.translate(:missing_html)

    assert_equal "<missing>", translation
    assert_not_predicate translation, :html_safe?
  end

  test "html_safe_translation_key detects html suffixes" do
    assert ActiveSupport::HtmlSafeTranslation.html_safe_translation_key?("title_html")
    assert ActiveSupport::HtmlSafeTranslation.html_safe_translation_key?("title.html")
    assert_not ActiveSupport::HtmlSafeTranslation.html_safe_translation_key?("html_title")
  end

  test "html safe translation handles arrays and plain objects" do
    translations = ActiveSupport::HtmlSafeTranslation.send(:html_safe_translation, ["<safe>", 1])

    assert_predicate translations.first, :html_safe?
    assert_equal 1, translations.last
    assert_equal 1, ActiveSupport::HtmlSafeTranslation.send(:html_safe_translation, 1)
  end
end
