# frozen_string_literal: true

require "abstract_unit"
require "tmpdir"

class ResolverPublicApiTest < ActiveSupport::TestCase
  class BasicResolver < ActionView::Resolver
    attr_reader :calls

    def initialize
      @calls = []
    end

    private
      def find_templates(name, prefix, partial, details, locals = [])
        @calls << [name, prefix, partial, details, locals]
        [:template]
      end
  end

  test "base resolver find_all normalizes to find_templates and clear_cache is a no op" do
    resolver = BasicResolver.new

    assert_equal [:template], resolver.find_all("show", "posts", true, { formats: [:html] }, nil, [:post])
    assert_equal [["show", "posts", true, { formats: [:html] }, [:post]]], resolver.calls
    assert_nil resolver.clear_cache
  end

  test "file system resolver rejects resolver instances as paths" do
    resolver = ActionView::FileSystemResolver.new(Dir.tmpdir)

    error = assert_raises(ArgumentError) { ActionView::FileSystemResolver.new(resolver) }

    assert_equal "path already is a Resolver class", error.message
  end

  test "file system resolver exposes expanded path identity and equality" do
    Dir.mktmpdir do |dir|
      same = ActionView::FileSystemResolver.new(dir)
      same_again = ActionView::FileSystemResolver.new(File.join(dir, "."))
      other = ActionView::FileSystemResolver.new(Dir.tmpdir)

      assert_equal File.expand_path(dir), same.to_s
      assert same.eql?(same_again)
      assert_equal same, same_again
      assert_not same.eql?(other)
      assert_not same.eql?(Object.new)
    end
  end

  test "file system resolver clear_cache resets path parser and cached templates" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "hello.html.erb"), "Hello")
      resolver = ActionView::FileSystemResolver.new(dir)

      details = { locale: [nil], formats: [:html], variants: [nil], handlers: [:erb] }

      assert_not_empty resolver.find_all("hello", "", false, details)
      assert_nil resolver.clear_cache
      assert_not_empty resolver.find_all("hello", "", false, details)
    end
  end

  test "path parser parses prefix partial locale format variant and handler" do
    parsed = ActionView::Resolver::PathParser.new.parse("admin/users/_card.en.html+phone.erb")

    assert_equal "admin/users/_card", parsed.path.virtual
    assert parsed.path.partial?
    assert_equal :en, parsed.details.locale
    assert_equal :html, parsed.details.format
    assert_equal :phone, parsed.details.variant
    assert_equal :erb, parsed.details.handler
  end
end
