# frozen_string_literal: true

require "abstract_unit"

class TemplateHandlersPublicApiTest < ActiveSupport::TestCase
  Handler = ->(_template, source) { source }

  test "template handler extensions are sorted strings" do
    ActionView::Template.register_template_handler :z_public_api, :a_public_api, Handler

    extensions = ActionView::Template.template_handler_extensions

    assert_includes extensions, "a_public_api"
    assert_includes extensions, "z_public_api"
    assert_operator extensions.index("a_public_api"), :<, extensions.index("z_public_api")
  ensure
    ActionView::Template.unregister_template_handler :z_public_api, :a_public_api
  end

  test "unregistering current default handler clears default handler fallback" do
    original_default = ActionView::Template.handler_for_extension(:unknown_public_api_extension)
    default_handler = ->(_template, source) { source }
    ActionView::Template.register_default_template_handler :public_api_default, default_handler

    assert_same default_handler, ActionView::Template.handler_for_extension(:unknown_public_api_extension)

    ActionView::Template.unregister_template_handler :public_api_default

    assert_nil ActionView::Template.registered_template_handler(:public_api_default)
    assert_nil ActionView::Template.handler_for_extension(:unknown_public_api_extension)
  ensure
    ActionView::Template.register_default_template_handler :raw, original_default if original_default
    ActionView::Template.unregister_template_handler :public_api_default
  end
end
