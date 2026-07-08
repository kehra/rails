# frozen_string_literal: true

require "abstract_unit"
require "controller/fake_models"
require "active_support/logger"
require "active_support/testing/ractors_assertions"

class RenderersTest < ActionController::TestCase
  include ActiveSupport::Testing::RactorsAssertions

  class XmlRenderable
    def to_xml(options)
      options[:root] ||= "i-am-xml"
      "<#{options[:root]}/>"
    end
  end

  class JsonRenderable
    def as_json(options = {})
      hash = { a: :b, c: :d, e: :f }
      hash.except!(*options[:except]) if options[:except]
      hash
    end

    def to_json(options = {})
      super except: [:c, :e]
    end
  end

  class CsvRenderable
    def to_csv
      "c,s,v"
    end
  end

  class JsRenderable
    def to_js(options)
      "alert(#{options[:message].inspect})"
    end
  end

  class MarkdownRenderable
    def to_markdown
      "# This is markdown"
    end
  end

  class SvgRenderable
    def to_svg
      "<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>"
    end
  end

  class TestController < ActionController::Base
    def render_simon_says
      render simon: "foo"
    end

    def respond_to_mime
      respond_to do |type|
        type.json do
          render json: JsonRenderable.new
        end
        type.js   { render json: "JS", callback: "alert" }
        type.csv  { render csv: CsvRenderable.new }
        type.xml  { render xml: XmlRenderable.new }
        type.md   { render markdown: MarkdownRenderable.new }
        type.svg  { render svg: SvgRenderable.new }
        type.html { render body: "HTML"    }
        type.rss  { render body: "RSS"     }
        type.all  { render body: "Nothing" }
        type.any(:js, :xml) { render body: "Either JS or XML" }
      end
    end

    def render_js_string
      render js: "window.Rails = {}"
    end

    def render_js_object
      render js: JsRenderable.new, message: "hello"
    end
  end

  tests TestController

  def setup
    # enable a logger so that (e.g.) the benchmarking stuff runs, so we can get
    # a more accurate simulation of what happens in "real life".
    super
    @controller.logger = ActiveSupport::Logger.new(nil)
  end

  def test_using_custom_render_option
    ActionController.add_renderer :simon do |says, options|
      self.content_type  = Mime[:text]
      self.response_body = "Simon says: #{says}"
    end

    get :render_simon_says
    assert_equal "Simon says: foo", @response.body
  ensure
    ActionController.remove_renderer :simon
  end

  def test_raises_missing_template_no_renderer
    assert_raise ActionView::MissingTemplate do
      get :respond_to_mime, format: "csv"
    end
    assert_equal Mime[:csv], @response.media_type
    assert_equal "", @response.body
  end

  def test_adding_csv_rendering_via_renderers_add
    ActionController::Renderers.add :csv do |value, options|
      send_data value.to_csv, type: Mime[:csv]
    end
    @request.accept = "text/csv"
    get :respond_to_mime, format: "csv"
    assert_equal Mime[:csv], @response.media_type
    assert_equal "c,s,v", @response.body
  ensure
    ActionController::Renderers.remove :csv
  end

  def test_missing_renderer_error_message
    error = ActionController::MissingRenderer.new(:csv)

    assert_equal "No renderer defined for format: csv", error.message
  end

  def test_renderers_class_attribute_accessors
    original_renderers = @controller.class._renderers
    original_escape_json_responses = @controller.class.escape_json_responses

    @controller.class._renderers = Set[:json]
    @controller._renderers = Set[:xml]
    @controller.class.escape_json_responses = false

    assert_equal Set[:xml], @controller._renderers
    assert_not @controller.class.escape_json_responses
  ensure
    @controller.class._renderers = original_renderers
    ActionController.deprecator.silence do
      @controller.class.escape_json_responses = original_escape_json_responses
    end
  end

  test "rendering js" do
    @request.accept = "text/javascript"
    get :respond_to_mime, format: "js"
    assert_equal Mime[:js], @response.media_type
    assert_equal "/**/alert(JS)", @response.body
  end

  test "rendering xml" do
    @request.accept = "application/xml"
    get :respond_to_mime, format: "xml"
    assert_equal Mime[:xml], @response.media_type
    assert_equal "<i-am-xml/>", @response.body
  end

  test "rendering js string" do
    get :render_js_string
    assert_equal Mime[:js], @response.media_type
    assert_equal "window.Rails = {}", @response.body
  end

  test "rendering js object" do
    get :render_js_object
    assert_equal Mime[:js], @response.media_type
    assert_equal "alert(\"hello\")", @response.body
  end

  test "rendering markdown" do
    get :respond_to_mime, format: "md"
    assert_equal Mime[:markdown], @response.media_type
    assert_equal "# This is markdown", @response.body
  end

  test "rendering svg" do
    get :respond_to_mime, format: "svg"
    assert_equal Mime[:svg], @response.media_type
    assert_equal "<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>", @response.body
  end

  test "accessing the RENDERERS constant is deprecated" do
    ActionController::Renderers.add(:foo) { }

    assert_deprecated(/ActionController::Renderers::RENDERERS is deprecated/, ActionController.deprecator) do
      assert_includes(ActionController::Renderers::RENDERERS, :foo)
    end
  ensure
    ActionController::Renderers.remove(:foo)
  end

  test "set of renderers if frozen" do
    assert_ractor_shareable(ActionController::Renderers.all)

    ActionController.add_renderer(:rtf) { }
    assert_ractor_shareable(ActionController::Renderers.all)

    ActionController.remove_renderer(:rtf)
    assert_ractor_shareable(ActionController::Renderers.all)
  end
end
