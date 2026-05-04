# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"

class PwaControllerTest < ActionController::TestCase
  tests Rails::PwaController

  def setup
    @view_root = Dir.mktmpdir("rails-pwa-controller-test")
    FileUtils.mkdir_p(File.join(@view_root, "pwa"))
    File.write(File.join(@view_root, "pwa", "offline.html.erb"), "<p>offline fallback</p>\n")
    FileUtils.mkdir_p(File.join(@view_root, "layouts"))
    File.write(File.join(@view_root, "layouts", "application.html.erb"), "<main>layout marker <%= yield %></main>\n")

    Rails.application.routes.draw do
      get "/offline" => "rails/pwa#offline"
    end
    @routes = Rails.application.routes
    @controller.prepend_view_path(@view_root)
  end

  def teardown
    FileUtils.rm_rf(@view_root) if @view_root
  end

  test "offline renders generated PWA page without application layout" do
    get :offline

    assert_response :success
    assert_equal "<p>offline fallback</p>\n", @response.body
    assert_no_match(/layout marker/, @response.body)
  end
end
