# frozen_string_literal: true

require "cases/helper"

class ActiveModelPublicApiTest < ActiveModel::TestCase
  test "eager_load loads active model and serializer eager autoloads" do
    assert_nothing_raised do
      ActiveModel.eager_load!
    end

    assert ActiveModel.const_defined?(:Errors)
    assert ActiveModel.const_defined?(:Error)
    assert ActiveModel::Serializers.const_defined?(:JSON)
  end
end
