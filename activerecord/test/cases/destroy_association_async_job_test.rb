# frozen_string_literal: true

require "cases/helper"
require "active_job"
require "active_record/destroy_association_async_job"
require "models/book_destroy_async"
require "models/essay_destroy_async"

class DestroyAssociationAsyncJobTest < ActiveRecord::TestCase
  setup do
    @old_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    ActiveJob::Base.queue_adapter = @old_queue_adapter
  end

  def test_perform_destroys_association_records_when_owner_is_absent
    essay = EssayDestroyAsync.create!(name: "orphaned")

    ActiveRecord::DestroyAssociationAsyncJob.perform_now(
      owner_model_name: "BookDestroyAsync",
      owner_id: -1,
      association_class: "EssayDestroyAsync",
      association_ids: [essay.id],
      association_primary_key_column: "id"
    )

    assert_nil EssayDestroyAsync.find_by(id: essay.id)
  end

  def test_perform_destroys_association_records_when_owner_check_passes
    BookDestroyAsync.class_eval { def async_destroy_allowed? = true }
    book = BookDestroyAsync.create!(name: "owner")
    essay = EssayDestroyAsync.create!(name: "owned", book: book)

    ActiveRecord::DestroyAssociationAsyncJob.perform_now(
      owner_model_name: "BookDestroyAsync",
      owner_id: book.id,
      association_class: "EssayDestroyAsync",
      association_ids: [essay.id],
      association_primary_key_column: "id",
      ensuring_owner_was_method: :async_destroy_allowed?
    )

    assert_nil EssayDestroyAsync.find_by(id: essay.id)
  ensure
    BookDestroyAsync.undef_method(:async_destroy_allowed?) if BookDestroyAsync.method_defined?(:async_destroy_allowed?)
  end

  def test_perform_raises_when_owner_still_exists_without_passing_check
    book = BookDestroyAsync.create!(name: "owner")
    essay = EssayDestroyAsync.create!(name: "owned", book: book)

    error = assert_raises(ActiveRecord::DestroyAssociationAsyncError) do
      ActiveRecord::DestroyAssociationAsyncJob.perform_now(
        owner_model_name: "BookDestroyAsync",
        owner_id: book.id,
        association_class: "EssayDestroyAsync",
        association_ids: [essay.id],
        association_primary_key_column: "id"
      )
    end

    assert_equal "owner record not destroyed", error.message
    assert_equal essay, EssayDestroyAsync.find(essay.id)
  end

  def test_perform_raises_when_owner_check_fails
    BookDestroyAsync.class_eval { def async_destroy_allowed? = false }
    book = BookDestroyAsync.create!(name: "owner")
    essay = EssayDestroyAsync.create!(name: "owned", book: book)

    assert_raises(ActiveRecord::DestroyAssociationAsyncError) do
      ActiveRecord::DestroyAssociationAsyncJob.perform_now(
        owner_model_name: "BookDestroyAsync",
        owner_id: book.id,
        association_class: "EssayDestroyAsync",
        association_ids: [essay.id],
        association_primary_key_column: "id",
        ensuring_owner_was_method: :async_destroy_allowed?
      )
    end

    assert_equal essay, EssayDestroyAsync.find(essay.id)
  ensure
    BookDestroyAsync.undef_method(:async_destroy_allowed?) if BookDestroyAsync.method_defined?(:async_destroy_allowed?)
  end
end
