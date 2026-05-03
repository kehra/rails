# frozen_string_literal: true

require "generators/generators_test_helper"
require "rails/generators/generated_attribute"

class TestingBehaviorPublicContractTest < Rails::Generators::TestCase
  include GeneratorsTestHelper

  class RecordingGenerator < Rails::Generators::Base
    argument :name, required: false

    class_attribute :starts, default: []

    def self.start(args, config = {})
      self.starts += [[args, config]]
      puts "started #{args.join(' ')}"
    end
  end

  tests RecordingGenerator
  arguments %w[post]
  destination File.expand_path("../tmp/behavior_public_contract", __dir__)
  setup :prepare_destination

  teardown do
    RecordingGenerator.starts = []
    ENV.delete("RAILS_LOG_TO_STDOUT")
  end

  test "class configuration stores generator default arguments and destination" do
    assert_equal RecordingGenerator, self.class.generator_class
    assert_equal %w[post], self.class.default_arguments
    assert_equal File.expand_path("../tmp/behavior_public_contract", __dir__), self.class.destination_root
  end

  test "run generator appends default skip flags and captures output by default" do
    output = run_generator

    assert_includes output, "started post --skip-bundle --skip-bootsnap"
    assert_equal [[%w[post --skip-bundle --skip-bootsnap], { destination_root: destination_root }]], RecordingGenerator.starts
  end

  test "run generator preserves explicit bundle and bootsnap arguments and can stream to stdout" do
    ENV["RAILS_LOG_TO_STDOUT"] = "true"

    output = capture(:stdout) do
      assert_nil run_generator(%w[post --no-skip-bundle --skip-bootsnap], custom: true)
    end

    assert_includes output, "started post --no-skip-bundle --skip-bootsnap"
    assert_equal [[%w[post --no-skip-bundle --skip-bootsnap], { destination_root: destination_root, custom: true }]], RecordingGenerator.starts

    RecordingGenerator.starts = []
    ENV.delete("RAILS_LOG_TO_STDOUT")
    run_generator(%w[post --dev])
    assert_equal %w[post --dev --skip-bootsnap], RecordingGenerator.starts.last.first
  end

  test "generator memoizes instances with destination root and generated attributes parse type name and index" do
    instance = generator(%w[comment], { behavior: :public }, custom: true)

    assert_same instance, generator(%w[other])
    assert_equal destination_root, instance.destination_root

    attribute = create_generated_attribute(:string, "title", "index")
    assert_equal "title", attribute.name
    assert_equal :string, attribute.type
    assert attribute.has_index?
  end

  test "private setup helpers prepare destination preserve current path and report missing destination" do
    FileUtils.touch(File.join(destination_root, "stale.txt"))
    prepare_destination
    assert_not File.exist?(File.join(destination_root, "stale.txt"))
    assert Dir.exist?(destination_root)

    Dir.mktmpdir("behavior-current-path") do |dir|
      FileUtils.cd(dir)
      ensure_current_path
      assert_equal self.class.current_path, Dir.pwd
    end

    FileUtils.mkdir_p(File.join(destination_root, "db/migrate"))
    File.write(File.join(destination_root, "db/migrate/20260503000000_create_posts.rb"), "")
    assert_equal File.join(destination_root, "db/migrate/20260503000000_create_posts.rb"), migration_file_name("db/migrate/create_posts.rb")

    previous_destination = self.class.destination_root
    self.class.destination_root = nil
    error = assert_raises(RuntimeError) { destination_root_is_set? }
    assert_equal "You need to configure your Rails::Generators::TestCase destination root.", error.message
  ensure
    self.class.destination_root = previous_destination if defined?(previous_destination)
    FileUtils.cd(self.class.current_path)
  end
end
