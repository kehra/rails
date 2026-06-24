# frozen_string_literal: true

require "abstract_unit"
require "abstract_controller/rendering"

class LookupContextTest < ActiveSupport::TestCase
  def setup
    @lookup_context = build_lookup_context(FIXTURE_LOAD_PATH, {})
    ActionView::LookupContext::DetailsKey.clear
  end

  def build_lookup_context(paths, details)
    ActionView::LookupContext.new(paths, details)
  end

  def teardown
    I18n.locale = :en
  end

  test "allows to override default_formats with ActionView::Base.default_formats" do
    formats = ActionView::Base.default_formats
    ActionView::Base.default_formats = [:foo, :bar]

    assert_equal [:foo, :bar], ActionView::LookupContext.new([]).default_formats
  ensure
    ActionView::Base.default_formats = formats
  end

  test "process view paths on initialization" do
    assert_kind_of ActionView::PathSet, @lookup_context.view_paths
  end

  test "normalizes details on initialization" do
    assert_equal Mime::SET.to_a, @lookup_context.formats
    assert_equal :en, @lookup_context.locale
  end

  test "allows me to freeze and retrieve frozen formats" do
    @lookup_context.formats.freeze
    assert_predicate @lookup_context.formats, :frozen?
  end

  test "provides getters and setters for variants" do
    @lookup_context.variants = [:mobile]
    assert_equal [:mobile], @lookup_context.variants
  end

  test "provides getters and setters for formats" do
    @lookup_context.formats = [:html]
    assert_equal [:html], @lookup_context.formats
  end

  test "handles */* formats" do
    @lookup_context.formats = ["*/*"]
    assert_equal Mime::SET.to_a, @lookup_context.formats
  end

  test "handles explicitly defined */* formats fallback to :js" do
    @lookup_context.formats = [:js, Mime::ALL]
    assert_equal [:js, *Mime::SET.symbols].uniq, @lookup_context.formats
  end

  test "adds :html fallback to :js formats" do
    @lookup_context.formats = [:js]
    assert_equal [:js, :html], @lookup_context.formats
  end

  test "raises on invalid format assignment" do
    ex = assert_raises ArgumentError do
      @lookup_context.formats = [:html, :invalid, "also bad"]
    end

    assert_equal 'Invalid formats: :invalid, "also bad"', ex.message
  end

  test "provides getters and setters for locale" do
    @lookup_context.locale = :pt
    assert_equal :pt, @lookup_context.locale
  end

  test "changing lookup_context locale, changes I18n.locale" do
    @lookup_context.locale = :pt
    assert_equal :pt, I18n.locale
  end

  test "delegates changing the locale to the I18n configuration object if it contains a lookup_context object" do
    begin
      I18n.config = ActionView::I18nProxy.new(I18n.config, @lookup_context)
      @lookup_context.locale = :pt
      assert_equal :pt, I18n.locale
      assert_equal :pt, @lookup_context.locale
    ensure
      I18n.config = I18n.config.original_config
    end

    assert_equal :pt, I18n.locale
  end

  test "find templates using the given view paths and configured details" do
    template = @lookup_context.find("hello_world", %w(test))
    assert_equal "Hello world!", template.source

    @lookup_context.locale = :da
    template = @lookup_context.find("hello_world", %w(test))
    assert_equal "Hey verden", template.source
  end

  test "find templates with given variants" do
    @lookup_context.formats  = [:html]
    @lookup_context.variants = [:phone]

    template = @lookup_context.find("hello_world", %w(test))
    assert_equal "Hello phone!", template.source

    @lookup_context.variants = [:phone]
    @lookup_context.formats  = [:text]

    template = @lookup_context.find("hello_world", %w(test))
    assert_equal "Hello texty phone!", template.source
  end

  test "found templates have nil format if one cannot be found from template or handler" do
    assert_called(ActionView::Template::Handlers::Builder, :default_format, returns: nil) do
      @lookup_context.formats = [:text]
      template = @lookup_context.find("hello", %w(test))
      assert_nil template.format
    end
  end

  test "generates a new details key for each details hash" do
    keys = []
    keys << @lookup_context.details_key
    assert_equal 1, keys.uniq.size

    @lookup_context.locale = :da
    keys << @lookup_context.details_key
    assert_equal 2, keys.uniq.size

    @lookup_context.locale = :en
    keys << @lookup_context.details_key
    assert_equal 2, keys.uniq.size

    @lookup_context.formats = [:html]
    keys << @lookup_context.details_key
    assert_equal 3, keys.uniq.size

    @lookup_context.formats = nil
    keys << @lookup_context.details_key
    assert_equal 3, keys.uniq.size
  end

  test "uses details as part of cache key" do
    fixtures = {
      "test/_foo.erb" => "Foo",
      "test/_foo.da.erb" => "Bar",
    }
    @lookup_context = build_lookup_context(ActionView::FixtureResolver.new(fixtures), {})

    template = @lookup_context.find("foo", %w(test), true)
    original_template = template
    assert_equal "Foo", template.source

    # We should get the same template
    template = @lookup_context.find("foo", %w(test), true)
    assert_same original_template, template

    # Using a different locale we get a different view
    @lookup_context.locale = :da
    template = @lookup_context.find("foo", %w(test), true)
    assert_equal "Bar", template.source

    # Using en we get the original view
    @lookup_context.locale = :en
    template = @lookup_context.find("foo", %w(test), true)
    assert_same original_template, template
  end

  test "can disable the cache on demand" do
    @lookup_context = build_lookup_context(ActionView::FixtureResolver.new("test/_foo.erb" => "Foo"), {})
    old_template = @lookup_context.find("foo", %w(test), true)

    template = @lookup_context.find("foo", %w(test), true)
    assert_equal template, old_template

    assert @lookup_context.cache
    template = @lookup_context.disable_cache do
      assert_not @lookup_context.cache
      @lookup_context.find("foo", %w(test), true)
    end
    assert @lookup_context.cache

    assert_not_equal template, old_template
  end

  test "lookup context public caches and derived contexts" do
    @lookup_context = build_lookup_context(ActionView::FixtureResolver.new("test/_foo.html.erb" => "Foo"), {})

    digest_cache = @lookup_context.digest_cache
    assert_same digest_cache, @lookup_context.digest_cache
    assert_includes ActionView::LookupContext::DetailsKey.digest_caches, digest_cache

    prepended = @lookup_context.with_prepended_formats([:json])
    assert_equal [:json], prepended.formats
    assert_equal @lookup_context.view_paths, prepended.view_paths
    assert_equal @lookup_context.prefixes, prepended.prefixes

    assert_same ActionView::LookupContext::DetailsKey.view_context_class, ActionView::LookupContext::DetailsKey.view_context_class
  end

  test "details key normalizes invalid requested formats" do
    details = { locale: [:en], formats: [:html, :invalid], variants: [], handlers: [:erb] }
    key = ActionView::LookupContext::DetailsKey.details_cache_key(details)

    assert_equal [:html], key.formats

    key_without_formats = ActionView::LookupContext::DetailsKey.details_cache_key(locale: [:en], formats: nil, variants: [], handlers: [:erb])
    assert_nil key_without_formats.formats
  end

  test "default locale skips fallbacks when i18n has no fallback support" do
    original_respond_to = I18n.method(:respond_to?)
    I18n.stub(:respond_to?, ->(name, *args) { name == :fallbacks ? false : original_respond_to.call(name, *args) }) do
      context = build_lookup_context([], {})
      assert_equal [I18n.locale], context.default_locale
    end
  end

  test "register detail defines default reader and writer" do
    detail_name = :lookup_context_test_detail
    original_default_procs = ActionView::LookupContext.default_procs

    ActionView::LookupContext.register_detail(detail_name) { [:default_value] }
    context = build_lookup_context([], {})

    assert_equal [:default_value], context.public_send(detail_name)
    context.public_send("#{detail_name}=", :custom_value)
    assert_equal [:custom_value], context.public_send(detail_name)
  ensure
    ActionView::LookupContext.default_procs = original_default_procs
  end

  test "lookup context view path public helpers delegate to path set" do
    resolver = ActionView::FixtureResolver.new(
      "test/_foo.html.erb" => "Foo",
      "admin/test/_foo.html.erb" => "Admin Foo",
      "other/_bar.html.erb" => "Bar"
    )
    @lookup_context = build_lookup_context(resolver, {})
    @lookup_context.formats = [:html]

    assert @lookup_context.exists?("foo", ["test"], true)
    assert @lookup_context.exists?("foo", ["test"], true, [], formats: [:html])
    assert @lookup_context.any?("foo", ["test"], true)
    assert_equal "Foo", @lookup_context.find("test/foo", [], true).source
    assert_equal "Admin Foo", @lookup_context.find("/test/foo", ["admin"], true).source
    assert_equal ["Foo"], @lookup_context.find_all("foo", ["test"], true).map(&:source)

    @lookup_context.disable_cache do
      assert @lookup_context.exists?("foo", ["test"], true, [], formats: [:html])
    end

    uncached_context = build_lookup_context(resolver, {})
    uncached_context.formats = [:html]
    uncached_context.disable_cache do
      assert uncached_context.any?("foo", ["test"], true)
    end

    @lookup_context.append_view_paths([ActionView::FixtureResolver.new("tail/_item.html.erb" => "Tail")])
    assert @lookup_context.exists?("item", ["tail"], true)

    @lookup_context.prepend_view_paths([ActionView::FixtureResolver.new("test/_foo.html.erb" => "Prepended")])
    assert_equal "Prepended", @lookup_context.find("foo", ["test"], true).source
  end

  test "any template lookup uses variant wildcard details" do
    @lookup_context = build_lookup_context(ActionView::FixtureResolver.new("test/_foo.html+phone.erb" => "Phone"), {})
    @lookup_context.formats = [:html]
    @lookup_context.variants = [:tablet]

    assert @lookup_context.any?("foo", ["test"], true)
  end

  test "locale can be cleared to default locale" do
    @lookup_context.locale = nil

    assert_equal I18n.default_locale, @lookup_context.locale
  end

  test "formats can be cleared to default formats" do
    @lookup_context.formats = nil

    assert_equal @lookup_context.default_formats, @lookup_context.formats
  end

  test "path set public collection operations" do
    resolver = ActionView::FixtureResolver.new("test/_foo.html.erb" => "Foo")
    other_resolver = ActionView::FixtureResolver.new("other/_bar.html.erb" => "Bar")
    path_set = ActionView::PathSet.new([resolver]).compact

    assert_equal [resolver], path_set.to_ary
    assert_not_same path_set.paths, path_set.to_ary

    copied = path_set.dup
    assert_equal path_set.paths, copied.paths
    assert_not_same path_set.paths, copied.paths

    added_from_array = path_set + [other_resolver]
    assert_equal [resolver, other_resolver], added_from_array.paths

    added_from_path_set = path_set + ActionView::PathSet.new([other_resolver])
    assert_equal [resolver, other_resolver], added_from_path_set.paths
  end

  test "path set lookup raises for missing templates and rejects invalid paths" do
    path_set = ActionView::PathSet.new([ActionView::FixtureResolver.new("test/_foo.html.erb" => "Foo")])
    details = { locale: [:en], formats: [:html], variants: [], handlers: [:erb] }
    details_key = ActionView::LookupContext::DetailsKey.details_cache_key(details)

    assert path_set.exists?("foo", ["test"], true, details, details_key, [])
    assert_equal ["Foo"], path_set.find_all("foo", ["test"], true, details, details_key, []).map(&:source)
    assert_equal "Foo", path_set.find("foo", ["test"], true, details, details_key, []).source

    assert_raises(ActionView::MissingTemplate) do
      path_set.find("missing", ["test"], true, details, details_key, [])
    end

    assert_raises(TypeError) do
      ActionView::PathSet.new([Object.new])
    end
  end

  test "responds to #prefixes" do
    assert_equal [], @lookup_context.prefixes
    @lookup_context.prefixes = ["foo"]
    assert_equal ["foo"], @lookup_context.prefixes
  end
end

class TestMissingTemplate < ActiveSupport::TestCase
  def setup
    @lookup_context = ActionView::LookupContext.new("/Path/to/views", {})
  end

  test "if no template was found we get a helpful error message including the inheritance chain" do
    e = assert_raise ActionView::MissingTemplate do
      @lookup_context.find!("foo", %w(parent child))
    end
    assert_match %r{Missing template parent/foo, child/foo with .*\n\nSearched in:\n  \* "/Path/to/views"\n}, e.message
  end

  test "if no partial was found we get a helpful error message including the inheritance chain" do
    e = assert_raise ActionView::MissingTemplate do
      @lookup_context.find!("foo", %w(parent child), true)
    end
    assert_match %r{Missing partial parent/_foo, child/_foo with .*\n\nSearched in:\n  \* "/Path/to/views"\n}, e.message
  end

  test "if a single prefix is passed as a string and the lookup fails, MissingTemplate accepts it" do
    e = assert_raise ActionView::MissingTemplate do
      details = { handlers: [], formats: [], variants: [], locale: [] }
      @lookup_context.view_paths.find!("foo", "parent", true, details, nil, [])
    end
    assert_match %r{Missing partial parent/_foo with .*\n\nSearched in:\n  \* "/Path/to/views"\n}, e.message
  end
end
