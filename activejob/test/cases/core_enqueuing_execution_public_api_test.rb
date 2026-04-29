# frozen_string_literal: true

require "helper"
require "jobs/hello_job"
require "active_support/core_ext/numeric/time"

class CoreEnqueuingExecutionPublicApiTest < ActiveSupport::TestCase
  class InlineReturnJob < ActiveJob::Base
    def perform(*values)
      values
    end
  end

  class NotImplementedJob < ActiveJob::Base
  end

  class HandledErrorJob < ActiveJob::Base
    rescue_from RuntimeError do
      "handled by rescue_from"
    end

    def perform
      raise "handled by rescue_from"
    end
  end

  class BulkAdapter
    attr_reader :jobs

    def enqueue(*)
      raise "enqueue should not be called when enqueue_all is available"
    end

    def enqueue_at(*)
      raise "enqueue_at should not be called when enqueue_all is available"
    end

    def enqueue_all(jobs)
      @jobs = jobs
      jobs.each { |job| job.successfully_enqueued = true }
      jobs.length
    end
  end

  class BulkJob < ActiveJob::Base
    class << self
      attr_accessor :adapter
    end

    self.adapter = BulkAdapter.new
    self.queue_adapter = adapter

    def perform
    end
  end

  class FallbackAdapter
    attr_reader :enqueued, :scheduled

    def initialize
      @enqueued = []
      @scheduled = []
    end

    def enqueue(job)
      raise ActiveJob::EnqueueError, "cannot enqueue" if job.arguments.first == :raise

      @enqueued << job
    end

    def enqueue_at(job, timestamp)
      @scheduled << [job, timestamp]
    end
  end

  class FallbackJob < ActiveJob::Base
    class << self
      attr_accessor :adapter
    end

    self.adapter = FallbackAdapter.new
    self.queue_adapter = adapter

    def perform(*)
    end
  end

  test "active job entry point exposes autoloads and verbose enqueue log setting" do
    assert_equal false, ActiveJob.verbose_enqueue_logs

    ActiveJob.verbose_enqueue_logs = true
    assert_equal true, ActiveJob.verbose_enqueue_logs
    assert_equal ActiveJob::Base, ActiveJob.const_get(:Base)
    assert_equal ActiveJob::QueueAdapters, ActiveJob.const_get(:QueueAdapters)
  ensure
    ActiveJob.verbose_enqueue_logs = false
  end

  test "core initialization and serialization preserve public job state" do
    Time.use_zone "Hawaii" do
      job = HelloJob.new("Rafael")

      assert_match(/\A[0-9a-f-]{36}\z/, job.job_id)
      assert_equal ["Rafael"], job.arguments
      assert_equal "default", job.queue_name
      assert_nil job.scheduled_at
      assert_equal 0, job.executions
      assert_equal({}, job.exception_executions)
      assert_equal "Hawaii", job.timezone
      assert_nil job.successfully_enqueued?

      job.provider_job_id = "provider-123"
      job.scheduled_at = Time.utc(2026, 4, 30, 1, 2, 3)
      job.priority = 7

      serialized = job.serialize
      assert_equal "HelloJob", serialized["job_class"]
      assert_equal "provider-123", serialized["provider_job_id"]
      assert_equal 7, serialized["priority"]
      assert_equal "Hawaii", serialized["timezone"]
      assert_equal job.scheduled_at.iso8601(9), serialized["scheduled_at"]
      assert_kind_of String, serialized["enqueued_at"]
    end
  end

  test "core set applies and skips options independently" do
    job = HelloJob.new
    original_queue = job.queue_name

    assert_same job, job.set
    assert_equal original_queue, job.queue_name
    assert_nil job.priority
    assert_nil job.scheduled_at

    scheduled = Time.utc(2026, 5, 1)
    job.set(wait: 5.minutes, wait_until: scheduled, queue: :urgent, priority: "3")

    assert_equal scheduled, job.scheduled_at
    assert_equal "urgent", job.queue_name
    assert_equal 3, job.priority
  end

  test "deserialize falls back to current timezone when payload omits timezone" do
    Time.use_zone "Hawaii" do
      job = HelloJob.new
      job.deserialize("arguments" => [])

      assert_equal "Hawaii", job.timezone
    end
  end

  test "deserialize falls back to current locale and nil timezone when payload omits them" do
    old_locales = I18n.available_locales

    I18n.available_locales = [:en, :es]
    I18n.locale = :es

    job = HelloJob.new
    original_time_zone = Time.method(:zone)
    original_verbose = $VERBOSE
    $VERBOSE = nil
    Time.define_singleton_method(:zone) { nil }
    $VERBOSE = original_verbose
    job.deserialize("arguments" => [])

    assert_equal "es", job.locale
    assert_nil job.timezone
  ensure
    $VERBOSE = nil
    Time.define_singleton_method(:zone, original_time_zone) if original_time_zone
    $VERBOSE = original_verbose
    I18n.available_locales = old_locales if old_locales
    I18n.locale = :en
  end

  test "class deserialize raises UnknownJobClassError with missing class name" do
    error = assert_raises(ActiveJob::UnknownJobClassError) do
      ActiveJob::Base.deserialize("job_class" => "MissingActiveJobClass")
    end

    assert_equal "MissingActiveJobClass", error.name
    assert_match(/MissingActiveJobClass/, error.message)
  end

  test "version deprecator and configured job public APIs" do
    assert_equal Gem::Version.new(ActiveJob::VERSION::STRING), ActiveJob.gem_version
    assert_equal ActiveJob.gem_version, ActiveJob.version
    assert_same ActiveJob.deprecator, ActiveJob.deprecator

    configured = InlineReturnJob.set(queue: :critical)
    assert_instance_of ActiveJob::ConfiguredJob, configured
    assert_equal ["configured", 1], configured.perform_now("configured", 1)

    enqueued = nil
    result = HelloJob.set(queue: :critical).perform_later("Configured") { |job| enqueued = job }
    assert_same result, enqueued
    assert_equal "critical", enqueued.queue_name
    assert_equal "Configured says hello", JobBuffer.last_value
  end

  test "class set returns configured job and perform_later accepts an existing job instance" do
    configured = HelloJob.set(queue: :critical)

    assert_instance_of ActiveJob::ConfiguredJob, configured

    job = HelloJob.new("Existing")
    returned = HelloJob.perform_later(job)

    assert_same job, returned
    assert_equal "Existing says hello", JobBuffer.last_value
  end

  test "perform_all_later delegates to adapters that implement enqueue_all" do
    adapter = BulkAdapter.new
    BulkJob.adapter = adapter
    BulkJob.queue_adapter = adapter
    jobs = [BulkJob.new, BulkJob.new]

    assert_nil ActiveJob.perform_all_later(jobs)
    assert_equal jobs, adapter.jobs
    assert_predicate jobs.first, :successfully_enqueued?
    assert_predicate jobs.second, :successfully_enqueued?
  end

  test "perform_all_later fallback enqueues immediate and scheduled jobs and captures enqueue errors" do
    adapter = FallbackAdapter.new
    FallbackJob.adapter = adapter
    FallbackJob.queue_adapter = adapter
    immediate = FallbackJob.new(:immediate)
    scheduled = FallbackJob.new(:scheduled).set(wait_until: Time.utc(2026, 5, 2))
    failing = FallbackJob.new(:raise)

    assert_nil ActiveJob.perform_all_later(immediate, scheduled, failing)

    assert_equal [immediate], adapter.enqueued
    assert_equal [[scheduled, scheduled.scheduled_at.to_f]], adapter.scheduled
    assert_predicate immediate, :successfully_enqueued?
    assert_predicate scheduled, :successfully_enqueued?
    assert_equal false, failing.successfully_enqueued?
    assert_instance_of ActiveJob::EnqueueError, failing.enqueue_error
  end

  test "perform_now class and instance APIs return perform result and deserialize stored arguments" do
    assert_equal ["class", 1], InlineReturnJob.perform_now("class", 1)

    serialized = InlineReturnJob.new("serialized", 2).serialize
    job = InlineReturnJob.deserialize(serialized)

    assert_equal ["serialized", 2], job.perform_now
    assert_equal 1, job.executions
  end

  test "perform_now returns rescue_from handler result" do
    handled = HandledErrorJob.perform_now

    assert_instance_of RuntimeError, handled
    assert_equal "handled by rescue_from", handled.message
  end

  test "default perform public API raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      NotImplementedJob.perform_now
    end
  end
end
