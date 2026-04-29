# frozen_string_literal: true

require "abstract_unit"

class DebugLocksTest < ActionDispatch::IntegrationTest
  setup do
    build_app
  end

  def test_passes_non_lock_requests_to_app
    app = ActionDispatch::DebugLocks.new(lambda { |_env| [200, {}, ["ok"]] })

    assert_equal [200, {}, ["ok"]], app.call(Rack::MockRequest.env_for("/elsewhere"))
    assert_equal [200, {}, ["ok"]], app.call(Rack::MockRequest.env_for("/rails/locks", method: "POST"))
  end

  def test_supports_custom_lock_path
    app = ActionDispatch::DebugLocks.new(lambda { |_env| [404, {}, []] }, "/custom/locks")

    status, headers, body = app.call(Rack::MockRequest.env_for("/custom/locks"))

    assert_equal 200, status
    assert_equal "text/plain; charset=utf-8", headers["content-type"]
    assert_respond_to body, :each
  end

  def test_render_threads_status
    thread_ready = Concurrent::CountDownLatch.new
    test_terminated = Concurrent::CountDownLatch.new

    thread = Thread.new do
      ActiveSupport::Dependencies.interlock.running do
        thread_ready.count_down
        test_terminated.wait
      end
    end

    thread_ready.wait

    get "/rails/locks"

    test_terminated.count_down

    assert_match(/Thread.*?Sharing/, @response.body)
  ensure
    thread.join
  end

  private
    def build_app
      @app = self.class.build_app do |middleware|
        middleware.use Rack::Lint
        middleware.use ActionDispatch::DebugLocks
        middleware.use Rack::Lint
      end
    end
end
