# frozen_string_literal: true

require "abstract_unit"
require "rails/api/task"
require "rake"

class RailsApiTaskPublicContractTest < ActiveSupport::TestCase
  setup do
    @old_pwd = Dir.pwd
    Dir.chdir(File.expand_path("../..", __dir__))
    @old_all = ENV["ALL"]
    @old_horo = ENV.values_at("HORO_PROJECT_NAME", "HORO_PROJECT_VERSION", "HORO_BADGE_VERSION", "HORO_CANONICAL_URL")
  end

  teardown do
    Dir.chdir(@old_pwd)
    ENV["ALL"] = @old_all
    %w[HORO_PROJECT_NAME HORO_PROJECT_VERSION HORO_BADGE_VERSION HORO_CANONICAL_URL].zip(@old_horo) { |key, value| ENV[key] = value }
  end

  test "edge and stable tasks expose version badge and canonical url" do
    edge = new_task(Rails::API::EdgeTask)
    assert_match(/\Amain@[0-9a-f]{7}\z/, edge.rails_version)
    assert_equal "edge", edge.badge_version
    assert_equal "https://edgeapi.rubyonrails.org", edge.canonical_url

    stable = new_task(Rails::API::StableTask)
    assert_equal File.read("RAILS_VERSION").strip, stable.rails_version
    assert_equal "v#{stable.rails_version}", stable.badge_version
    assert_equal "https://api.rubyonrails.org/#{stable.badge_version}", stable.canonical_url
  end

  test "repo task configures paths and sdoc github option" do
    task = new_task(Rails::API::RepoTask)

    assert_equal "railties", task.component_root_dir("railties")
    assert_equal "doc/rdoc", task.api_dir

    task.configure_sdoc

    assert_equal "Ruby on Rails API", task.title
    assert_equal "doc/rdoc", task.rdoc_dir
    assert_includes task.options, "-g"
    assert_option_pair task.options, "-m", "railties/RDOC_MAIN.md"
    assert_option_pair task.options, "-e", "UTF-8"
    assert_option_pair task.options, "-f", "api"
    assert_option_pair task.options, "-T", "rails"
  end

  test "base task api main description and horo environment" do
    task = new_task(Rails::API::StableTask)

    assert_nil task.desc("ignored by API task")
    assert_equal "railties/RDOC_MAIN.md", task.api_main

    task.setup_horo_variables

    assert_equal "Ruby on Rails", ENV["HORO_PROJECT_NAME"]
    assert_equal task.rails_version, ENV["HORO_PROJECT_VERSION"]
    assert_equal task.badge_version, ENV["HORO_BADGE_VERSION"]
    assert_equal task.canonical_url, ENV["HORO_CANONICAL_URL"]
  end

  test "initializer registers lazy rdoc configuration hook" do
    task = new_task(Rails::API::StableTask)
    calls = []
    task.define_singleton_method(:configure_sdoc) { calls << :configure_sdoc }
    task.define_singleton_method(:configure_rdoc_files) { calls << :configure_rdoc_files }
    task.define_singleton_method(:setup_horo_variables) { calls << :setup_horo_variables }

    task.instance_variable_get(:@before_running_rdoc).call

    assert_equal [:configure_sdoc, :configure_rdoc_files, :setup_horo_variables], calls
  end

  test "configure rdoc files includes configured component files and api main without timestamp" do
    task = new_task(Rails::API::RepoTask)

    task.configure_rdoc_files
    files = task.rdoc_files.to_a

    assert_includes files, "activesupport/README.rdoc"
    assert_includes files, "activerecord/lib/arel.rb"
    assert_includes files, "railties/lib/rails.rb"
    assert_includes files, "railties/RDOC_MAIN.md"
    refute_includes files, "railties/lib/rails/test_unit/*"
  end

  test "configure rdoc files keeps files newer than existing timestamp" do
    Dir.mktmpdir do |dir|
      old_file = File.join(dir, "old.rb")
      new_file = File.join(dir, "new.rb")
      api_dir = File.join(dir, "api")
      timestamp = File.join(api_dir, "created.rid")
      FileUtils.mkdir_p(api_dir)
      File.write(old_file, "# old\n")
      File.write(new_file, "# new\n")
      generation_time = Time.now
      File.write(timestamp, generation_time.rfc2822)
      File.utime(generation_time - 3600, generation_time - 3600, old_file)
      File.utime(generation_time + 3600, generation_time + 3600, new_file)

      task = new_task(Rails::API::RepoTask)
      task.define_singleton_method(:api_dir) { api_dir }
      task.define_singleton_method(:api_main) { new_file }
      task.define_singleton_method(:configure_component_rdoc_files) do
        rdoc_files.include(old_file)
        rdoc_files.include(new_file)
      end
      task.define_singleton_method(:configure_rdoc_files) do
        configure_component_rdoc_files
        super()
      end
      task.configure_rdoc_files

      assert_equal [new_file], task.rdoc_files.to_a.uniq
    end
  end

  test "configure rdoc files exits when timestamp leaves no changed files" do
    Dir.mktmpdir do |dir|
      old_file = File.join(dir, "old.rb")
      api_dir = File.join(dir, "api")
      FileUtils.mkdir_p(api_dir)
      File.write(old_file, "# old\n")
      future = Time.now + 10 * 365 * 24 * 60 * 60
      File.write(File.join(api_dir, "created.rid"), future.rfc2822)
      File.utime(future - 3600, future - 3600, old_file)

      task = new_task(Rails::API::RepoTask)
      task.define_singleton_method(:api_dir) { api_dir }
      task.define_singleton_method(:rdoc_files) { @rdoc_files ||= Rake::FileList[old_file] }
      exits = []
      task.define_singleton_method(:exit) { |status| exits << status; throw :api_task_exit }

      catch(:api_task_exit) { task.configure_rdoc_files }
      assert_equal [0], exits
    end
  end

  test "configure rdoc files ignores timestamp when ALL is set" do
    Dir.mktmpdir do |dir|
      old_file = File.join(dir, "old.rb")
      api_dir = File.join(dir, "api")
      FileUtils.mkdir_p(api_dir)
      File.write(old_file, "# old\n")
      File.write(File.join(api_dir, "created.rid"), Time.now.rfc2822)
      File.utime(Time.now - 3600, Time.now - 3600, old_file)
      ENV["ALL"] = "1"

      task = new_task(Rails::API::RepoTask)
      task.define_singleton_method(:api_dir) { api_dir }
      task.define_singleton_method(:api_main) { old_file }
      task.define_singleton_method(:rdoc_files) { @rdoc_files ||= Rake::FileList[old_file] }

      task.configure_rdoc_files
      assert_includes task.rdoc_files.to_a, old_file
    end
  end

  private
    def new_task(klass)
      klass.new("api_contract_#{klass.name.demodulize.underscore}_#{object_id}_#{rand(1_000_000)}")
    end

    def assert_option_pair(options, flag, value)
      index = options.index(flag)
      assert index, "expected #{flag.inspect} in #{options.inspect}"
      assert_equal value, options[index + 1]
    end
end
