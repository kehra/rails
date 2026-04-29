# frozen_string_literal: true

require "abstract_unit"
require "active_support/ordered_options"
require "action_dispatch"

ActionView::Template.mime_types_implementation = Mime

class AssetTagPublicApiTest < ActionView::TestCase
  tests ActionView::Helpers::AssetTagHelper

  class FakeRequest
    attr_accessor :content_security_policy_nonce_directives

    def protocol = "http://"
    def ssl? = false
    def host_with_port = "example.com"
    def base_url = "http://example.com"

    def send_early_hints(links)
      @early_hints = links
    end

    attr_reader :early_hints
  end

  class FakeResponse
    attr_reader :headers

    def initialize(sending: false)
      @sending = sending
      @headers = {}
    end

    def sending? = @sending
  end

  attr_accessor :request, :response

  def setup
    super
    @controller = BasicController.new
    @request = FakeRequest.new
    @response = FakeResponse.new
    @controller.request = @request
    @controller.response = @response
  end

  def url_for(*) = "http://example.com/feed"
  def content_security_policy_nonce = defined?(@nonce) ? @nonce : "nonce-value"
  def polymorphic_url(record) = "/records/#{record.to_param}"

  test "asset tag helpers render media and discovery tags" do
    assert_includes audio_tag("song.mp3"), '<audio src="/audios/song.mp3"></audio>'
    assert_includes audio_tag("song.mp3", "song.ogg"), '<source src="/audios/song.mp3" />'
    assert_includes favicon_link_tag("icon.png", rel: "apple-touch-icon", type: "image/png"), 'rel="apple-touch-icon"'

    assert_raises(ArgumentError) { auto_discovery_link_tag(:custom) }
    assert_includes auto_discovery_link_tag(:custom, {}, type: "application/custom"), 'type="application/custom"'
  end

  test "stylesheet and javascript tags exercise preload option branches" do
    assert_includes stylesheet_link_tag("site", crossorigin: true, preload_links_header: false), 'crossorigin="anonymous"'
    assert_includes javascript_include_tag("app", defer: true, preload_links_header: true, nonce: false), '<script src="/javascripts/app.js" defer="defer"></script>'
  end

  test "preload link tag resolves inferred as types and header states" do
    @request.content_security_policy_nonce_directives = ["script-src"]
    assert_includes preload_link_tag("app.js"), 'nonce="nonce-value"'
    assert_includes @response.headers["link"], "as=script"

    @response = FakeResponse.new(sending: true)
    assert_includes preload_link_tag("captions.vtt"), 'as="track"'
    assert_nil @response.headers["link"]

    @response = nil
    @request = nil
    @nonce = nil
    assert_includes preload_link_tag("unknown.custom", as: "fetch", type: nil), 'as="fetch"'
  end

  test "image picture and video tags cover source variants" do
    record = Struct.new(:to_param).new("7")

    assert_includes image_tag(record), 'src="/records/7"'
    assert_includes image_tag("icon.png", srcset: { "icon@2x.png" => "2x" }, size: "16"), 'width="16"'
    assert_raises(ArgumentError) { image_tag("icon.png", size: "16", width: "32") }

    assert_includes picture_tag("plain", "fallback"), '<source srcset="/images/plain" />'
    assert_includes picture_tag { tag(:source, srcset: "/manual.webp") }, '<source srcset="/manual.webp" />'

    assert_includes video_tag("clip.mp4", size: "10x20", poster: "poster.png"), 'poster="/images/poster.png"'
  end

  test "asset url helpers cover skip pipeline roots and custom hosts" do
    @controller.config.relative_url_root = "/assets_root"

    assert_equal "/assets_root/javascripts/app.js", asset_path("app", type: :javascript, skip_pipeline: true)
    assert_equal "/assets_root/logo.png", asset_path("/logo.png")
    assert_equal "/assets_root/logo.png", asset_path("/assets_root/logo.png")

    hoster = Class.new do
      def call(_source, _request = nil)
        "cdn.example.com"
      end
    end.new

    assert_equal "https://cdn.example.com", compute_asset_host("/logo.png", host: hoster, protocol: "https")

    @controller.config.default_asset_host_protocol = "https"
    assert_equal "https://assets.example.com", compute_asset_host("/logo.png", host: "assets.example.com")

    @controller.config.default_asset_host_protocol = nil
    @request = nil
    assert_equal "//assets.example.com", compute_asset_host("/logo.png", host: "assets.example.com")
  ensure
    @controller.config.relative_url_root = nil
    @controller.config.default_asset_host_protocol = nil
  end
end
