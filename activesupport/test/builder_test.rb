# frozen_string_literal: true

require_relative "abstract_unit"
require "active_support/builder"

class BuilderTest < ActiveSupport::TestCase
  def test_builder_entrypoint_loads_xml_markup
    assert_kind_of Builder::XmlMarkup, Builder::XmlMarkup.new
  end
end
