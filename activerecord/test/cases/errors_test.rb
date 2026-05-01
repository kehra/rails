# frozen_string_literal: true

require "cases/helper"
require "active_record/errors"
require "active_record/associations/errors"

class ErrorsTest < ActiveRecord::TestCase
  def test_eager_load_polymorphic_error_message_without_reflection
    error = ActiveRecord::EagerLoadPolymorphicError.new

    assert_equal "Eager load polymorphic error.", error.message
  end

  def test_can_be_instantiated_with_no_args
    base = ActiveRecord::ActiveRecordError
    error_klasses = ObjectSpace.each_object(Class).select { |klass| klass < base }

    expected_to_be_initializable_with_no_args = error_klasses - [
      ActiveRecord::AmbiguousSourceReflectionForThroughAssociation,
      ActiveRecord::DeprecatedAssociationError
    ]
    assert_nothing_raised do
      expected_to_be_initializable_with_no_args.each do |error_klass|
        error_klass.new.inspect
      rescue ArgumentError
        raise "Instance of #{error_klass} can't be initialized with no arguments"
      end
    end
  end
end
