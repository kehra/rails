# frozen_string_literal: true

module ConnectionHelper
  def run_without_connection
    original_configuration = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.remove_connection
    yield original_configuration
  ensure
    ActiveRecord::Base.establish_connection(original_configuration)
  end

  # Used to drop all cache query plans in tests.
  def reset_connection
    original_configuration = ActiveRecord::Base.connection_db_config.configuration_hash
    ActiveRecord::Base.remove_connection
    ActiveRecord::Base.establish_connection(original_configuration)
  end
end
