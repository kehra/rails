# frozen_string_literal: true

require_relative "abstract_unit"

module ActiveSupport
  class ProxyLoggerTest < TestCase
    setup do
      @io = StringIO.new
      @real_logger = Logger.new(@io)
      @logger = ProxyLogger.new(@real_logger)
    end

    def test_own_level_interface
      @real_logger.debug("REAL-1")
      @logger.debug("PROXY-1")

      @logger.level = :error

      @real_logger.debug("REAL-2")
      @logger.debug("PROXY-2")

      assert_equal %w(REAL-1 PROXY-1 REAL-2), @io.string.split("\n")
    end

    def test_initialize_accepts_own_level
      logger = ProxyLogger.new(@real_logger, :warn)

      assert_equal Logger::WARN, logger.level
      assert_not logger.info?
      assert logger.warn?
    end

    def test_level_predicates_and_bang_setters
      @logger.fatal!
      assert_equal Logger::FATAL, @logger.level
      assert_not @logger.error?
      assert @logger.fatal?

      @logger.error!
      assert_equal Logger::ERROR, @logger.level
      assert_not @logger.warn?
      assert @logger.error?

      @logger.warn!
      assert_equal Logger::WARN, @logger.level
      assert_not @logger.info?
      assert @logger.warn?

      @logger.info!
      assert_equal Logger::INFO, @logger.level
      assert_not @logger.debug?
      assert @logger.info?

      @logger.debug!
      assert_equal Logger::DEBUG, @logger.level
      assert @logger.debug?
    end

    def test_underlying_level_interface
      @real_logger.debug("REAL-1")
      @logger.debug("PROXY-1")

      @real_logger.level = :error

      @real_logger.debug("REAL-2")
      @logger.debug("PROXY-2")

      assert_equal %w(REAL-1 PROXY-1), @io.string.split("\n")
    end

    def test_silence
      @logger.silence do
        @logger.info("SILENCED")
        @logger.error("PASSES")
      end
      @logger.info("AFTER")

      assert_equal %w(PASSES AFTER), @io.string.split("\n")
    end

    def test_silence_only_affects_the_receiver
      other = ProxyLogger.new(@real_logger)
      @logger.silence do
        other.info("OTHER")
      end

      assert_equal %w(OTHER), @io.string.split("\n")
    end

    def test_close_and_reopen
      @logger.debug("BEFORE")
      @logger.close
      @logger.debug("CLOSED")
      @logger.reopen(@real_logger)
      @logger.debug("AFTER")

      assert_equal %w(BEFORE AFTER), @io.string.split("\n")
    end

    def test_all_delegators
      @logger.debug("DEBUG")
      @logger.info("INFO")
      @logger.warn("WARN")
      @logger.error("ERROR")
      @logger.fatal("FATAL")
      @logger.unknown("UNKNOWN")
      assert_equal %w(DEBUG INFO WARN ERROR FATAL UNKNOWN), @io.string.split("\n")
    end

    def test_all_block_delegators
      @logger.debug { "DEBUG" }
      @logger.info { "INFO" }
      @logger.warn { "WARN" }
      @logger.error { "ERROR" }
      @logger.fatal { "FATAL" }
      @logger.unknown { "UNKNOWN" }
      assert_equal %w(DEBUG INFO WARN ERROR FATAL UNKNOWN), @io.string.split("\n")
    end

    def test_add_respects_proxy_level
      @logger.level = :error

      @logger.add(Logger::WARN, "WARN")
      @logger.add(Logger::ERROR, "ERROR")

      assert_equal %w(ERROR), @io.string.split("\n")
    end

    def test_append_writes_to_underlying_logger
      @logger << "APPEND\n"

      assert_equal %w(APPEND), @io.string.split("\n")
    end
  end
end
