require "test_helper"

class UnifiedLogger::JobLoggerTest < UnifiedLoggerTestCase
  def setup
    super
    @logger, @io = create_test_logger
    UnifiedLogger.stubs(:current_logger).returns(@logger)
    @attrs = { class_name: "TestJob", id: "abc-123", queue: "default", params: [1, "two"],
               enqueued_at: 1.minute.ago.iso8601 }
  end

  # -- Basic behavior --

  test "yields to the block" do
    called = false
    UnifiedLogger::JobLogger.log(**@attrs) { called = true }
    assert called
  end

  test "returns the block return value" do
    result = UnifiedLogger::JobLogger.log(**@attrs) { 42 }
    assert_equal 42, result
  end

  test "writes log to logger" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal "job", log["log_type"]
  end

  test "does not write log when current_logger is not UnifiedLogger::Logger" do
    UnifiedLogger.stubs(:current_logger).returns(::Logger.new(StringIO.new))
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }

    @io.rewind
    assert_empty @io.read
  end

  test "class_name is the only required argument" do
    UnifiedLogger::JobLogger.log(class_name: "MinimalJob") { "work" }
    log = parsed_log_from(@io)
    assert_equal "MinimalJob", log["class_name"]
    assert_equal "ok", log["status"]
  end

  # -- Log content --

  test "log includes class_name" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal "TestJob", log["class_name"]
  end

  test "log includes id" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal "abc-123", log["id"]
  end

  test "log includes queue" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal "default", log["queue"]
  end

  test "log includes params" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal [1, "two"], log["params"]
  end

  test "log includes retry_count" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal 0, log["retry_count"]
  end

  test "log includes timestamp" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert log.key?("timestamp")
  end

  test "log includes thread_id and process_id" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal Thread.current.object_id, log["thread_id"]
    assert_equal Process.pid, log["process_id"]
  end

  # -- Duration --

  test "duration measures execution time" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["duration"]
    assert log["duration"] >= 0
  end

  test "queue_duration is calculated when enqueued_at is present" do
    UnifiedLogger::JobLogger.log(**@attrs, enqueued_at: 5.minutes.ago.iso8601) { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["queue_duration"]
    assert log["queue_duration"].positive?
  end

  test "queue_duration is omitted when enqueued_at is nil" do
    UnifiedLogger::JobLogger.log(**@attrs.except(:enqueued_at)) { "work" }
    log = parsed_log_from(@io)
    assert_not log.key?("queue_duration")
  end

  # -- enqueued_at normalization --

  test "enqueued_at as epoch float produces valid queue_duration" do
    UnifiedLogger::JobLogger.log(**@attrs, enqueued_at: 5.minutes.ago.to_f) { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["queue_duration"]
    assert log["queue_duration"].positive?
  end

  test "enqueued_at as ISO 8601 string produces valid queue_duration" do
    UnifiedLogger::JobLogger.log(**@attrs, enqueued_at: 5.minutes.ago.iso8601) { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["queue_duration"]
  end

  test "enqueued_at as Time object produces valid queue_duration" do
    UnifiedLogger::JobLogger.log(**@attrs, enqueued_at: 5.minutes.ago) { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["queue_duration"]
  end

  # -- Status --

  test "status is ok when no exception" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal "ok", log["status"]
  end

  test "status is error when exception and no max_retries" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs) { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "error", log["status"]
  end

  test "status is warn when exception and retries remaining" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs, retry_count: 2, max_retries: 5) { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "warn", log["status"]
  end

  test "status is error when exception and retries exhausted" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs, retry_count: 5, max_retries: 5) { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "error", log["status"]
  end

  test "status is error when exception and retry_count exceeds max_retries" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs, retry_count: 10, max_retries: 5) { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "error", log["status"]
  end

  # -- Exception handling --

  test "includes exception details when block raises" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs) { raise "boom" }
    end
    log = parsed_log_from(@io)
    assert_equal "RuntimeError", log["exception"]["class_name"]
    assert_equal "boom", log["exception"]["message"]
  end

  test "re-raises the exception" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs) { raise "boom" }
    end
  end

  test "logs even when exception occurs" do
    assert_raises(RuntimeError) do
      UnifiedLogger::JobLogger.log(**@attrs) { raise "boom" }
    end

    @io.rewind
    assert_not_empty @io.read
  end

  # -- Logs integration --

  test "includes logs when present" do
    UnifiedLogger::JobLogger.log(**@attrs) do
      @logger.info("inside job")
    end
    log = parsed_log_from(@io)
    assert log.key?("logs")
    assert_equal 1, log["logs"].size
  end

  test "resets logs after job" do
    UnifiedLogger::JobLogger.log(**@attrs) do
      @logger.info("inside")
    end
    assert_empty UnifiedLogger::Logger.logs
  end

  test "omits logs key when no logs" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_not log.key?("logs")
  end

  # -- Extra log fields integration --

  test "merges extra_log_fields into job log" do
    UnifiedLogger::JobLogger.log(**@attrs) do
      UnifiedLogger::Logger.add(user_id: 123, batch_id: "xyz")
    end
    log = parsed_log_from(@io)
    assert_equal 123, log["user_id"]
    assert_equal "xyz", log["batch_id"]
  end

  test "resets extra_log_fields after job" do
    UnifiedLogger::JobLogger.log(**@attrs) do
      UnifiedLogger::Logger.add(user_id: 123)
    end
    assert_empty UnifiedLogger::Logger.extra_log_fields
  end

  test "omits extra fields when none set" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_not log.key?("user_id")
  end

  # -- Extra kwargs passthrough --

  test "extra kwargs are merged into log" do
    UnifiedLogger::JobLogger.log(**@attrs, locale: "en", exception_executions: {}) { "work" }
    log = parsed_log_from(@io)
    assert_equal "en", log["locale"]
    assert_equal({}, log["exception_executions"])
  end

  test "nil extra kwargs are compacted out" do
    UnifiedLogger::JobLogger.log(**@attrs, locale: nil) { "work" }
    log = parsed_log_from(@io)
    assert_not log.key?("locale")
  end

  # -- Transform job log callable --

  test "calls transform_job_log_callable with log payload" do
    UnifiedLogger.transform_job_log = ->(log) { log[:extra] = true }
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    log = parsed_log_from(@io)
    assert_equal true, log["extra"]
  end

  test "works when transform_job_log_callable is nil" do
    UnifiedLogger::JobLogger.log(**@attrs) { "work" }
    assert_nothing_raised { parsed_log_from(@io) }
  end

  # -- Log size overflow --

  test "splits large logs into overflow lines" do
    UnifiedLogger::JobLogger.log(**@attrs) do
      200.times { |i| @logger.info("entry-#{i}-#{"x" * 100}") }
    end

    @io.rewind
    lines = @io.readlines
    assert lines.size > 1, "Expected overflow lines"

    main = JSON.parse(lines.first)
    assert_not main.key?("logs")
    assert_equal "job", main["log_type"]

    overflow = JSON.parse(lines[1])
    assert_equal main["id"], overflow["id"]
    assert_equal "job", overflow["log_type"]
    assert_equal 1, overflow["index"]
  end
end
