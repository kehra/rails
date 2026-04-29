# frozen_string_literal: true

require "abstract_unit"
require "action_view/template_details"
require "action_view/template_path"

class TemplateDetailsPublicApiTest < ActiveSupport::TestCase
  HandlerWithDefaultFormat = Struct.new(:default_format)

  setup do
    @old_handler = ActionView::Template.registered_template_handler(:details_default)
    ActionView::Template.register_template_handler(:details_default, HandlerWithDefaultFormat.new(:json))
  end

  teardown do
    if @old_handler
      ActionView::Template.register_template_handler(:details_default, @old_handler)
    else
      ActionView::Template.unregister_template_handler(:details_default)
    end
  end

  test "requested builds lookup indexes and any variants wildcard" do
    requested = ActionView::TemplateDetails::Requested.new(locale: [:en], handlers: [:erb], formats: [:html], variants: :any)

    assert_equal [:en], requested.locale
    assert_equal 0, requested.locale_idx[:en]
    assert_equal 1, requested.locale_idx[nil]
    assert_equal 0, requested.handlers_idx[:erb]
    assert_equal 0, requested.formats_idx[:html]
    assert_equal 1, requested.variants_idx[:phone]
    assert_equal 0, requested.variants_idx[nil]
  end

  test "template details match requested details and expose sort key" do
    requested = ActionView::TemplateDetails::Requested.new(locale: [:en], handlers: [:erb], formats: [:html], variants: [:phone])
    details = ActionView::TemplateDetails.new(:en, :erb, :html, :phone)

    assert_equal :en, details.locale
    assert_equal :erb, details.handler
    assert_equal :html, details.format
    assert_equal :phone, details.variant
    assert details.matches?(requested)
    assert_equal [0, 0, 0, 0], details.sort_key_for(requested)
  end

  test "template details use handler default format when format is absent" do
    details = ActionView::TemplateDetails.new(nil, :details_default, nil, nil)

    assert_equal HandlerWithDefaultFormat, details.handler_class.class
    assert_equal :json, details.format_or_default
    assert_equal :xml, ActionView::TemplateDetails.new(nil, :details_default, :xml, nil).format_or_default
  end
end

class TemplatePathPublicApiTest < ActiveSupport::TestCase
  test "virtual builds names with prefix and partial combinations" do
    assert_equal "show", ActionView::TemplatePath.virtual("show", "", false)
    assert_equal "_show", ActionView::TemplatePath.virtual("show", "", true)
    assert_equal "admin/show", ActionView::TemplatePath.virtual("show", "admin", false)
    assert_equal "admin/_show", ActionView::TemplatePath.virtual("show", "admin", true)
  end

  test "build creates a template path from separate parts" do
    path = ActionView::TemplatePath.build("show", "admin", true)

    assert_equal "show", path.name
    assert_equal "admin", path.prefix
    assert_predicate path, :partial?
    assert_equal "admin/_show", path.virtual
    assert_equal "admin/_show", path.virtual_path
    assert_equal "admin/_show", path.to_s
    assert_equal "admin/_show", path.to_str
  end

  test "parse handles prefixed partial absolute paths and plain names" do
    partial = ActionView::TemplatePath.parse("/admin/users/_card")
    plain = ActionView::TemplatePath.parse("index")

    assert_equal "card", partial.name
    assert_equal "admin/users", partial.prefix
    assert_predicate partial, :partial?
    assert_equal "/admin/users/_card", partial.virtual

    assert_equal "index", plain.name
    assert_equal "", plain.prefix
    assert_not plain.partial?
    assert_equal "index", plain.virtual
  end

  test "template path equality and hash are based on virtual path" do
    one = ActionView::TemplatePath.build("show", "admin", false)
    two = ActionView::TemplatePath.parse("admin/show")

    assert_equal one, two
    assert_equal one.hash, two.hash
  end
end
