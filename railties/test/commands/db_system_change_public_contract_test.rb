# frozen_string_literal: true

require "abstract_unit"
require "rails/command"
require "rails/commands/db/system/change/change_command"

class DbSystemChangePublicContractTest < ActiveSupport::TestCase
  setup do
    @started_with = []
    @original_start = Rails::Generators::Db::System::ChangeGenerator.method(:start)
    starts = @started_with
    Rails::Generators::Db::System::ChangeGenerator.singleton_class.define_method(:start) do |argv|
      starts << argv
    end
  end

  teardown do
    Rails::Generators::Db::System::ChangeGenerator.singleton_class.send(:remove_method, :start)
    original = @original_start
    Rails::Generators::Db::System::ChangeGenerator.singleton_class.define_method(:start) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  test "initializes with positional and option arguments and delegates perform to generator" do
    command = Rails::Command::Db::System::ChangeCommand.new(["change"], ["--to=postgresql", "--force"], {})

    command.perform

    assert_equal [["change", "--to=postgresql", "--force"]], @started_with
  end
end
