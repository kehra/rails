# frozen_string_literal: true

require "abstract_unit"
require "rails/autoloaders"

class AutoloadersPublicContractTest < ActiveSupport::TestCase
  test "initializes main and once zeitwerk loaders with rails tags and inflector" do
    autoloaders = Rails::Autoloaders.new

    assert_instance_of Zeitwerk::Loader, autoloaders.main
    assert_equal "rails.main", autoloaders.main.tag
    assert_equal Rails::Autoloaders::Inflector, autoloaders.main.inflector
    assert_instance_of Zeitwerk::Loader, autoloaders.once
    assert_equal "rails.once", autoloaders.once.tag
    assert_equal Rails::Autoloaders::Inflector, autoloaders.once.inflector
    assert_equal [autoloaders.main, autoloaders.once], autoloaders.to_a
    assert_predicate autoloaders, :zeitwerk_enabled?
  end

  test "logger assignment and log mode are applied to both loaders" do
    autoloaders = Rails::Autoloaders.new
    logger = Object.new

    autoloaders.logger = logger
    assert_equal logger, autoloaders.main.logger
    assert_equal logger, autoloaders.once.logger

    autoloaders.log!
    assert_instance_of Proc, autoloaders.main.logger
    assert_instance_of Proc, autoloaders.once.logger
  end
end
