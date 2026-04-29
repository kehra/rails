# frozen_string_literal: true

require "abstract_unit"
require "action_dispatch/testing/assertion_response"

class AssertionResponseTest < ActiveSupport::TestCase
  test "initializes from symbolic generic response name" do
    response = ActionDispatch::AssertionResponse.new(:success)

    assert_equal :success, response.name
    assert_equal "2XX", response.code
    assert_equal "2XX: success", response.code_and_name
  end

  test "initializes from symbolic rack status name" do
    response = ActionDispatch::AssertionResponse.new(:created)

    assert_equal :created, response.name
    assert_equal 201, response.code
    assert_equal "201: created", response.code_and_name
  end

  test "initializes from generic response code" do
    response = ActionDispatch::AssertionResponse.new("404")

    assert_equal :missing, response.name
    assert_equal "404", response.code
    assert_equal "404: missing", response.code_and_name
  end

  test "initializes from numeric rack status code" do
    response = ActionDispatch::AssertionResponse.new(201)

    assert_equal "Created", response.name
    assert_equal 201, response.code
    assert_equal "201: Created", response.code_and_name
  end

  test "raises for unknown response names and codes" do
    assert_raises(ArgumentError, match: /Unrecognized status code/) do
      ActionDispatch::AssertionResponse.new(:bogus)
    end

    no_code_response = Class.new(ActionDispatch::AssertionResponse) do
      private
        def code_from_name(*)
          nil
        end
    end

    assert_raises(ArgumentError, match: /Invalid response name/) do
      no_code_response.new(:unknown)
    end

    assert_raises(ArgumentError, match: /Invalid response code/) do
      ActionDispatch::AssertionResponse.new(799)
    end
  end
end
