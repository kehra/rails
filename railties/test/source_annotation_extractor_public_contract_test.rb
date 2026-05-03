# frozen_string_literal: true

require "abstract_unit"
require "rails/source_annotation_extractor"

class SourceAnnotationExtractorPublicContractTest < ActiveSupport::TestCase
  setup do
    @root = Dir.mktmpdir("source-annotation-extractor")
    @original_directories = Rails::SourceAnnotationExtractor::Annotation.directories.dup
    @original_tags = Rails::SourceAnnotationExtractor::Annotation.tags.dup
    @original_extensions = Rails::SourceAnnotationExtractor::Annotation.extensions.dup
  end

  teardown do
    Rails::SourceAnnotationExtractor::Annotation.directories.replace(@original_directories)
    Rails::SourceAnnotationExtractor::Annotation.tags.replace(@original_tags)
    Rails::SourceAnnotationExtractor::Annotation.extensions.replace(@original_extensions)
    FileUtils.rm_rf(@root)
  end

  test "annotation registries append directories tags and extensions" do
    annotation = Rails::SourceAnnotationExtractor::Annotation

    annotation.register_directories("spec", "extras")
    annotation.register_tags("REVIEW", "SECURITY")
    annotation.register_extensions("txt", "text") { |tag| /--\s*(#{tag}):?\s*(.*)$/ }

    assert_includes annotation.directories, "spec"
    assert_includes annotation.directories, "extras"
    assert_includes annotation.tags, "REVIEW"
    assert_includes annotation.tags, "SECURITY"
    assert annotation.extensions.keys.any? { |regexp| regexp.match?("notes.text") }
  end

  test "annotation string includes optional tag and line indentation" do
    annotation = Rails::SourceAnnotationExtractor::Annotation.new(7, "TODO", "tighten contract")

    assert_equal "[ 7] tighten contract", annotation.to_s(indent: 2)
    assert_equal "[  7] [TODO] tighten contract", annotation.to_s(indent: 3, tag: true)
  end

  test "pattern extractor returns matching file annotations" do
    file = write_file("notes.yml", <<~YAML)
      key: value
      # TODO: from yaml
      # NOPE: ignored
      # FIXME from yaml without colon
    YAML

    extractor = Rails::SourceAnnotationExtractor::PatternExtractor.new(/#\s*(TODO|FIXME):?\s*(.*)$/)
    annotations = extractor.annotations(file)

    assert_equal [2, 4], annotations.map(&:line)
    assert_equal ["TODO", "FIXME"], annotations.map(&:tag)
    assert_equal ["from yaml", "from yaml without colon"], annotations.map(&:text)
  end

  test "parser extractor returns ruby comments and ignores invalid ruby" do
    ruby = write_file("model.rb", <<~RUBY)
      class Model
        # TODO: parser note
        def value = 1 # FIXME: inline parser note
      end
    RUBY
    invalid = write_file("broken.rb", "class Broken\n  def")

    extractor = Rails::SourceAnnotationExtractor::ParserExtractor.new(/#\s*(TODO|FIXME):?\s*(.*)$/)

    assert_equal [[2, "TODO", "parser note"], [3, "FIXME", "inline parser note"]], extractor.annotations(ruby).map { |a| [a.line, a.tag, a.text] }
    assert_empty extractor.annotations(invalid)
  end

  test "find_in recursively scans visible registered files and skips unsupported and empty patterns" do
    write_file("app/models/user.rb", "# TODO: model note")
    write_file("app/models/readme.md", "# TODO: ignored extension")
    write_file("app/models/.hidden.rb", "# TODO: hidden note")
    write_file("app/views/users/show.erb", "<% # FIXME: erb note %>")
    write_file("app/assets/stylesheets/application.css", "/* TODO: css note */")
    write_file("app/assets/javascripts/application.js", "// TODO: js note")
    write_file("config/settings.yml", "# TODO: yml note")
    write_file("config/skipped.skip", "SKIP TODO: skipped pattern")

    Rails::SourceAnnotationExtractor::Annotation.register_extensions("skip") { |_tag| nil }

    extractor = Rails::SourceAnnotationExtractor.new("TODO|FIXME")
    results = relative_results(extractor.find_in(File.join(@root, "app"))).merge(relative_results(extractor.find_in(File.join(@root, "config"))))

    assert_equal ["app/assets/javascripts/application.js", "app/assets/stylesheets/application.css", "app/models/user.rb", "app/views/users/show.erb", "config/settings.yml"], results.keys.sort
    assert_equal "model note", results["app/models/user.rb"].first.text
    assert_equal "erb note", results["app/views/users/show.erb"].first.text
  end

  test "find_in skips hidden entries returned by glob" do
    hidden = File.join(@root, ".hidden.rb")
    singleton = class << Dir; self; end
    original_glob = Dir.method(:glob)
    singleton.define_method(:glob) do |_pattern, &block|
      block.call(hidden)
      []
    end

    assert_empty Rails::SourceAnnotationExtractor.new("TODO").find_in(@root)
  ensure
    singleton.define_method(:glob) { |*args, **kwargs, &block| original_glob.call(*args, **kwargs, &block) } if original_glob
  end

  test "find merges directories and display sorts files with shared indentation" do
    write_file("app/models/user.rb", "\n# TODO: user model")
    write_file("lib/task.rb", "\n" * 10 + "# FIXME: library task")

    extractor = Rails::SourceAnnotationExtractor.new("TODO|FIXME")
    results = extractor.find([File.join(@root, "lib"), File.join(@root, "app")])

    output = capture_io do
      extractor.display(results, tag: true)
    end.first

    assert_equal <<~OUTPUT, output
      #{@root}/app/models/user.rb:
        * [ 2] [TODO] user model

      #{@root}/lib/task.rb:
        * [11] [FIXME] library task

    OUTPUT
  end

  test "enumerate uses default tags and directories unless options override them" do
    write_file("notes/default.rb", "# TODO: default note")
    write_file("custom/custom.txt", "-- REVIEW: custom note")
    Rails::SourceAnnotationExtractor::Annotation.register_directories(File.join(@root, "notes"))
    Rails::SourceAnnotationExtractor::Annotation.register_tags("REVIEW")
    Rails::SourceAnnotationExtractor::Annotation.register_extensions("txt") { |tag| /--\s*(#{tag}):?\s*(.*)$/ }

    default_output = capture_io do
      Rails::SourceAnnotationExtractor.enumerate(nil, tag: true)
    end.first
    custom_output = capture_io do
      Rails::SourceAnnotationExtractor.enumerate("REVIEW", dirs: [File.join(@root, "custom")])
    end.first

    assert_includes default_output, "notes/default.rb"
    assert_includes default_output, "[TODO] default note"
    assert_includes custom_output, "custom/custom.txt"
    assert_includes custom_output, "custom note"
    assert_not_includes custom_output, "[REVIEW]"
  end

  private
    def write_file(relative, content)
      path = File.join(@root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    def relative_results(results)
      results.transform_keys { |path| path.delete_prefix("#{@root}/") }
    end
end
