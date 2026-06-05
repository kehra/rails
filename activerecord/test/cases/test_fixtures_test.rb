# frozen_string_literal: true

require "cases/helper"
require "tempfile"
require "fileutils"
require "models/zine"

class TestFixturesTest < ActiveRecord::TestCase
  self.use_transactional_tests = false

  setup do
    @klass = Class.new
    @klass.include(ActiveRecord::TestFixtures)
  end

  def test_use_transactional_tests_defaults_to_true
    assert_equal true, @klass.use_transactional_tests
  end

  def test_use_transactional_tests_can_be_overridden
    @klass.use_transactional_tests = "foobar"

    assert_equal "foobar", @klass.use_transactional_tests
  end

  def test_inclusion_runs_active_record_fixtures_load_hook
    ActiveSupport.on_load(:active_record_fixtures) do
      self.fixture_paths << "test/fixtures"
    end
    klass = Class.new

    klass.include(ActiveRecord::TestFixtures)

    assert_includes klass.fixture_paths, "test/fixtures"
  end

  def test_transactional_tests_per_database_class_methods
    @klass.use_transactional_tests_for_database :animals
    @klass.skip_transactional_tests_for_database :plants

    assert_equal({ animals: true, plants: false }, @klass.database_transactions_config)
  end

  def test_set_fixture_class_merges_stringified_fixture_names
    @klass.set_fixture_class some_fixture: Zine
    @klass.set_fixture_class "namespaced/fixture" => Zine

    assert_equal({ "some_fixture" => Zine, "namespaced/fixture" => Zine }, @klass.fixture_class_names)
  end

  def test_fixtures_registers_explicit_names_and_accessors
    @klass.fixtures :accounts, ["admin/users"]

    assert_equal %w[accounts admin/users], @klass.fixture_table_names
    assert_equal({ "accounts" => "accounts", "admin_users" => "admin/users" }, @klass.fixture_sets)
  end

  def test_fixtures_all_requires_fixture_paths
    @klass.fixture_paths = []

    error = assert_raises(StandardError) { @klass.fixtures :all }

    assert_includes error.message, "No fixture path found"
  end

  def test_fixtures_all_discovers_yaml_files_and_skips_file_fixtures
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p File.join(dir, "admin")
      FileUtils.mkdir_p File.join(dir, "files")
      File.write File.join(dir, "accounts.yml"), "one: {}\n"
      File.write File.join(dir, "admin", "users.yml"), "one: {}\n"
      File.write File.join(dir, "files", "avatar.yml"), "one: {}\n"

      @klass.fixture_paths = [dir]
      @klass.define_singleton_method(:file_fixture_path) { File.join(dir, "files") }

      @klass.fixtures :all

      assert_equal %w[accounts admin/users], @klass.fixture_table_names
      assert_equal({ "accounts" => "accounts", "admin_users" => "admin/users" }, @klass.fixture_sets)
    end
  end

  def test_fixtures_all_discovers_yaml_files_without_file_fixture_path
    Dir.mktmpdir do |dir|
      File.write File.join(dir, "accounts.yml"), "one: {}\n"

      @klass.fixture_paths = [dir]
      @klass.fixtures :all

      assert_equal %w[accounts], @klass.fixture_table_names
    end
  end

  def test_setup_fixture_accessors_handles_symbols_slashes_defaults_and_empty_input
    @klass.fixture_table_names = [:accounts, "admin/users"]
    @klass.setup_fixture_accessors

    assert_equal({ "accounts" => "accounts", "admin_users" => "admin/users" }, @klass.fixture_sets)

    previous_sets = @klass.fixture_sets
    @klass.setup_fixture_accessors([])

    assert_same previous_sets, @klass.fixture_sets
  end

  def test_uses_transaction_tracks_method_names
    fresh_class = Class.new
    fresh_class.include(ActiveRecord::TestFixtures)
    fresh_class.uses_transaction :first_without_transaction
    assert fresh_class.uses_transaction?(:first_without_transaction)

    assert_not @klass.uses_transaction?(:other_test)

    @klass.uses_transaction :test_without_transaction, "test_also_without_transaction"
    @klass.uses_transaction :test_third_without_transaction

    assert @klass.uses_transaction?(:test_without_transaction)
    assert @klass.uses_transaction?("test_also_without_transaction")
    assert @klass.uses_transaction?(:test_third_without_transaction)
    assert_not @klass.uses_transaction?(:other_test)
  end

  def test_fixture_accessor_fetches_single_multiple_all_reload_and_missing_records
    fixture_class = Struct.new(:record) do
      attr_reader :finds

      def find
        @finds = finds.to_i + 1
        record
      end
    end
    fixture_set = Struct.new(:fixtures) do
      def [](name)
        fixtures[name]
      end
    end
    one = fixture_class.new("one record")
    two = fixture_class.new("two record")
    test_case = @klass.new
    @klass.fixture_sets = { "books" => "books" }
    test_case.instance_variable_set(:@fixture_cache, {})
    test_case.instance_variable_set(:@loaded_fixtures, { "books" => fixture_set.new({ "one" => one, "two" => two }) })

    assert_equal "one record", test_case.fixture(:books, :one)
    assert_equal "one record", test_case.fixture(:books, "one")
    assert_equal 1, one.finds
    assert_equal "one record", test_case.fixture(:books, "one", :reload)
    assert_equal 2, one.finds
    assert_equal ["one record", "two record"], test_case.fixture(:books)
    assert_equal ["one record", "two record"], test_case.fixture(:books, "one", "two")

    assert_raises(StandardError) { test_case.fixture(:books, "missing") }
    assert_raises(StandardError) { test_case.fixture(:unknown, "one") }
  end

  unless in_memory_db?
    def test_doesnt_rely_on_active_support_test_case_specific_methods
      tmp_dir = Dir.mktmpdir
      File.write(File.join(tmp_dir, "zines.yml"), <<~YML)
      going_out:
        title: Hello
      YML

      klass = Class.new(Minitest::Test) do
        include ActiveRecord::TestFixtures

        self.fixture_paths = [tmp_dir]
        self.use_transactional_tests = true

        fixtures :all

        def test_run_successfully
          assert_equal("Hello", Zine.first.title)
          assert_equal("Hello", zines(:going_out).title)
        end
      end

      ActiveSupport::Notifications.unsubscribe(@connection_subscriber)
      @connection_subscriber = nil

      old_handler = ActiveRecord::Base.connection_handler
      ActiveRecord::Base.connection_handler = ActiveRecord::ConnectionAdapters::ConnectionHandler.new
      ActiveRecord::Base.establish_connection(:arunit)

      test_result = klass.new("test_run_successfully").run
      assert_predicate(test_result, :passed?)
    ensure
      ActiveRecord::Base.connection_handler = old_handler
      clean_up_connection_handler
      FileUtils.rm_r(tmp_dir)
    end

    def test_teardown_shared_connection_pool_disconnects_pool_configs_for_removed_roles
      handler = ActiveRecord::Base.connection_handler
      db_config = ActiveRecord::Base.configurations.configs_for(env_name: "arunit", name: "primary")
      pool_manager = handler.instance_variable_get(:@connection_name_to_pool_manager)["ActiveRecord::Base"]
      writing_pool_config = pool_manager.get_pool_config(:writing, :default)
      reading_pool_config = ActiveRecord::ConnectionAdapters::PoolConfig.new(ActiveRecord::Base, db_config, :reading, :default)
      pool_manager.set_pool_config(:reading, :default, reading_pool_config)

      reading_pool = reading_pool_config.pool
      connection = reading_pool.checkout
      connection.execute("SELECT 1")
      reading_pool.checkin(connection)

      setup_shared_connection_pool
      assert_same writing_pool_config, pool_manager.get_pool_config(:reading, :default)

      clean_up_connection_handler
      teardown_shared_connection_pool

      assert_predicate writing_pool_config.pool, :automatic_reconnect
      assert_not_predicate reading_pool, :connected?
    ensure
      teardown_shared_connection_pool if defined?(@saved_pool_configs) && @saved_pool_configs.any?
      clean_up_connection_handler
    end

    def test_transactional_tests_per_db_explicitly_disabled
      tmp_dir = Dir.mktmpdir
      File.write(File.join(tmp_dir, "zines.yml"), <<~YML)
      going_out:
        title: Hello
      YML

      klass = Class.new(Minitest::Test) do
        include ActiveRecord::TestFixtures

        self.fixture_paths = [tmp_dir]
        self.use_transactional_tests = true
        self.skip_transactional_tests_for_database :primary

        fixtures :all

        def test_run_successfully
          assert_equal("Hello", Zine.first.title)
          assert_equal("Hello", zines(:going_out).title)
          # Change the data in the primary connection
          Zine.first.update!(title: "Goodbye")
        end
      end

      test_result = klass.new("test_run_successfully").run
      assert_predicate(test_result, :passed?)
      # Ensure that the primary connection was NOT rolled back
      assert_equal("Goodbye", Zine.first.title)
    ensure
      FileUtils.rm_r(tmp_dir)
    end

    def test_transactional_tests_per_db_explicitly_enabled
      tmp_dir = Dir.mktmpdir
      File.write(File.join(tmp_dir, "zines.yml"), <<~YML)
      going_out:
        title: Hello
      YML

      klass = Class.new(Minitest::Test) do
        include ActiveRecord::TestFixtures

        self.fixture_paths = [tmp_dir]
        self.use_transactional_tests = false
        self.use_transactional_tests_for_database :primary

        fixtures :all

        def test_run_successfully
          assert_equal("Hello", Zine.first.title)
          assert_equal("Hello", zines(:going_out).title)
          # Change the data in the primary connection
          Zine.first.update!(title: "Goodbye")
        end
      end

      test_result = klass.new("test_run_successfully").run
      assert_predicate(test_result, :passed?)
      # Ensure that the primary connection WAS rolled back
      assert_equal("Hello", Zine.first.title)
    ensure
      FileUtils.rm_r(tmp_dir)
    end

    def test_transactional_tests_per_db_default_enabled
      tmp_dir = Dir.mktmpdir
      File.write(File.join(tmp_dir, "zines.yml"), <<~YML)
      going_out:
        title: Hello
      YML

      klass = Class.new(Minitest::Test) do
        include ActiveRecord::TestFixtures

        self.fixture_paths = [tmp_dir]
        self.use_transactional_tests = true
        self.skip_transactional_tests_for_database :unrelated

        fixtures :all

        def test_run_successfully
          assert_equal("Hello", Zine.first.title)
          assert_equal("Hello", zines(:going_out).title)
          # Change the data in the primary connection
          Zine.first.update!(title: "Goodbye")
        end
      end

      test_result = klass.new("test_run_successfully").run
      assert_predicate(test_result, :passed?)
      # Ensure that the primary connection WAS rolled back
      assert_equal("Hello", Zine.first.title)
    ensure
      FileUtils.rm_r(tmp_dir)
    end

    def test_transactional_tests_per_db_default_disabled
      tmp_dir = Dir.mktmpdir
      File.write(File.join(tmp_dir, "zines.yml"), <<~YML)
      going_out:
        title: Hello
      YML

      klass = Class.new(Minitest::Test) do
        include ActiveRecord::TestFixtures

        self.fixture_paths = [tmp_dir]
        self.use_transactional_tests = false
        self.use_transactional_tests_for_database :unrelated

        fixtures :all

        def test_run_successfully
          assert_equal("Hello", Zine.first.title)
          assert_equal("Hello", zines(:going_out).title)
          # Change the data in the primary connection
          Zine.first.update!(title: "Goodbye")
        end
      end

      test_result = klass.new("test_run_successfully").run
      assert_predicate(test_result, :passed?)
      # Ensure that the primary connection was NOT rolled back
      assert_equal("Goodbye", Zine.first.title)
    ensure
      FileUtils.rm_r(tmp_dir)
    end
  end
end
