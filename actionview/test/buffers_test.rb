# frozen_string_literal: true

require "abstract_unit"

module SharedBufferTests
  def self.included(test_case)
    test_case.test "#<< maintains HTML safety" do
      @buffer << nil
      assert_equal "", output

      @buffer << "<p>safe</p>".html_safe
      assert_equal "<p>safe</p>", output

      @buffer << "<script>alert('pwned!')</script>"
      assert_predicate @buffer, :html_safe?
      assert_predicate output, :html_safe?
      assert_equal "<p>safe</p>&lt;script&gt;alert(&#39;pwned!&#39;)&lt;/script&gt;", output
    end

    test_case.test "#safe_append= bypasses HTML safety" do
      @buffer.safe_append = "<p>This is fine</p>"
      assert_predicate @buffer, :html_safe?
      assert_predicate output, :html_safe?
      assert_equal "<p>This is fine</p>", output
    end

    test_case.test "#raw allow to bypass HTML escaping" do
      raw_buffer = @buffer.raw
      assert_same raw_buffer, raw_buffer.raw
      raw_buffer << nil
      assert_equal "", output

      raw_buffer << "<script>alert('pwned!')</script>"
      assert_predicate @buffer, :html_safe?
      assert_predicate output, :html_safe?
      assert_equal "<script>alert('pwned!')</script>", output
    end

    test_case.test "#capture allow to intercept writes" do
      @buffer << "Hello"
      result = @buffer.capture do
        @buffer << "George!"
      end
      assert_equal "George!", result
      assert_predicate result, :html_safe?

      @buffer << " World!"
      assert_equal "Hello World!", output
    end

    test_case.test "#raw respects #capture" do
      @buffer << "Hello"
      raw_buffer = @buffer.raw
      result = @buffer.capture do
        raw_buffer << "George!"
      end
      assert_equal "George!", result
      assert_predicate result, :html_safe?

      @buffer << " World!"
      assert_equal "Hello World!", output
    end
  end
end

class TestOutputBuffer < ActiveSupport::TestCase
  include SharedBufferTests

  setup do
    @buffer = ActionView::OutputBuffer.new
  end

  test "can be duped" do
    @buffer << "Hello"
    copy = @buffer.dup
    copy << " World!"
    assert_equal "Hello World!", copy.to_s
    assert_equal "Hello", output
  end

  test "supports equality only with same class and string content" do
    @buffer << "Hello"
    assert_equal ActionView::OutputBuffer.new("Hello"), @buffer
    assert_not_equal ActiveSupport::SafeBuffer.new("Hello"), @buffer
    assert_not_equal ActionView::OutputBuffer.new("Goodbye"), @buffer
  end

  test "safe_expr_append appends string values without escaping and ignores nil" do
    assert_same @buffer, @buffer.__send__(:safe_expr_append=, nil)
    assert_equal "", output

    assert_same @buffer, @buffer.__send__(:safe_expr_append=, "<p>safe expr</p>")
    assert_equal "<p>safe expr</p>", output
  end

  private
    def output
      @buffer.to_s
    end
end

class TestStreamingBuffer < ActiveSupport::TestCase
  include SharedBufferTests

  setup do
    @raw_buffer = +""
    @buffer = ActionView::StreamingBuffer.new(@raw_buffer.method(:<<))
  end

  test "html_safe returns the streaming buffer itself" do
    assert_same @buffer, @buffer.html_safe
  end

  private
    def output
      @raw_buffer.html_safe
    end
end
