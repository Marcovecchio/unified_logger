require "test_helper"

class UnifiedLogger::JobLoggerTest < UnifiedLoggerTestCase
  def setup
    super
    @logger, @io = create_test_logger
    UnifiedLogger.stubs(:current_logger).returns(@logger)
    @job = build_fake_job
  end

  # -- Basic behavior --

  test "yields to the block" do
    called = false
    UnifiedLogger::JobLogger.log(@job) { called = true }
    assert called
  end

  test "returns the block return value" do
    result = UnifiedLogger::JobLogger.log(@job) { 42 }
    assert_equal 42, result
  end

  test "writes log to logger" do
    UnifiedLogger::JobLogger.log(@job) { "work" }

    log = parsed_log_from(@io)
    assert_equal "job", log["log_type"]
  end

  test "does not write log when current_logger is not UnifiedLogger::Logger" do
    UnifiedLogger.stubs(:current_logger).returns(::Logger.new(StringIO.new))
    UnifiedLogger::JobLogger.log(@job) { "work" }

    @io.rewind
    assert_empty @io.read
  end

  # -- Log content --

  test "log includes class_name" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal "FakeJob", log["class_name"]
  end

  test "log includes job_id" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal "abc-123", log["id"]
  end

  test "log includes queue" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal "default", log["queue"]
  end

  test "log includes arguments as params" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal [1, "two"], log["params"]
  end

  test "log includes executions_count" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal 0, log["executions_count"]
  end

  test "log includes locale" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal "en", log["locale"]
  end

  # -- Duration --

  test "duration is calculated from enqueued_at" do
    job = build_fake_job(enqueued_at: 5.minutes.ago.iso8601)
    UnifiedLogger::JobLogger.log(job) { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["duration"]
    assert log["duration"].positive?
  end

  test "duration is unknown when enqueued_at is nil" do
    job = build_fake_job(enqueued_at: nil)
    UnifiedLogger::JobLogger.log(job) { "work" }
    log = parsed_log_from(@io)
    assert_equal "unknown", log["duration"]
  end

  # -- Status --

  test "status is ok when no exception" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal "ok", log["status"]
  end

  test "status is warn when exception and executions below max retries" do
    job = build_fake_job(executions: 2)
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(job) { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "warn", log["status"]
  end

  test "status is error when exception and executions at max retries" do
    job = build_fake_job(executions: 5)
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(job) { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "error", log["status"]
  end

  test "DEFAULT_MAX_RETRIES is 5" do
    assert_equal 5, UnifiedLogger::JobLogger::DEFAULT_MAX_RETRIES
  end

  # -- Exception handling --

  test "includes exception details when block raises" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(@job) { raise "boom" }
    end
    log = parsed_log_from(@io)
    assert_equal "RuntimeError", log["exception"]["class_name"]
    assert_equal "boom", log["exception"]["message"]
  end

  test "re-raises the exception" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(@job) { raise "boom" }
    end
  end

  test "logs even when exception occurs" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(@job) { raise "boom" }
    end

    @io.rewind
    assert_not_empty @io.read
  end

  # -- Custom logs integration --

  test "includes custom logs when present" do
    UnifiedLogger::JobLogger.log(@job) do
      @logger.info("inside job")
    end
    log = parsed_log_from(@io)
    assert log.key?("custom")
    assert_equal 1, log["custom"].size
  end

  test "resets custom logs after job" do
    UnifiedLogger::JobLogger.log(@job) do
      @logger.info("inside")
    end
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "omits custom key when no custom logs" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_not log.key?("custom")
  end

  # -- Transform job log callable --

  test "calls transform_job_log_callable with log payload" do
    UnifiedLogger.transform_job_log = ->(log) { log[:extra] = true }
    UnifiedLogger::JobLogger.log(@job) { "work" }
    log = parsed_log_from(@io)
    assert_equal true, log["extra"]
  end

  test "works when transform_job_log_callable is nil" do
    UnifiedLogger::JobLogger.log(@job) { "work" }
    assert_nothing_raised { parsed_log_from(@io) }
  end
end
