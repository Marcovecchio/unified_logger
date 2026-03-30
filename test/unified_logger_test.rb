require "test_helper"

class UnifiedLoggerTest < UnifiedLoggerTestCase
  # -- Configuration --

  test "config returns default values on first access" do
    config = UnifiedLogger.config
    assert_equal 2048, config[:max_log_field_size]
    assert_equal 10_000, config[:max_log_size]
    assert_includes config[:filter_params], :passw
    assert_includes config[:filter_params], :secret
    assert_includes config[:filter_params], :token
    assert_equal true, config[:auto_insert_middleware]
    assert_equal [], config[:silence_paths]
  end

  test "config returns the same mutable hash on repeated calls" do
    assert_same UnifiedLogger.config, UnifiedLogger.config
  end

  test "configure merges options into config" do
    UnifiedLogger.configure(max_log_field_size: 512)
    assert_equal 512, UnifiedLogger.config[:max_log_field_size]
    assert_equal true, UnifiedLogger.config[:auto_insert_middleware]
  end

  test "DEFAULTS is frozen" do
    assert_predicate UnifiedLogger::DEFAULTS, :frozen?
  end

  # -- Callable setters --

  test "transform_request_log= stores the callable" do
    callable = ->(log, _env) { log[:extra] = true }
    UnifiedLogger.transform_request_log = callable
    assert_same callable, UnifiedLogger.transform_request_log_callable
  end

  test "transform_request_log= raises DoubleDefineError on second assignment" do
    UnifiedLogger.transform_request_log = -> {}
    assert_raises(UnifiedLogger::DoubleDefineError) { UnifiedLogger.transform_request_log = -> {} }
  end

  test "transform_request_log_callable is nil by default" do
    assert_nil UnifiedLogger.transform_request_log_callable
  end

  test "transform_job_log= stores the callable" do
    callable = ->(log) { log[:extra] = true }
    UnifiedLogger.transform_job_log = callable
    assert_same callable, UnifiedLogger.transform_job_log_callable
  end

  test "transform_job_log= raises DoubleDefineError on second assignment" do
    UnifiedLogger.transform_job_log = -> {}
    assert_raises(UnifiedLogger::DoubleDefineError) { UnifiedLogger.transform_job_log = -> {} }
  end

  test "transform_job_log_callable is nil by default" do
    assert_nil UnifiedLogger.transform_job_log_callable
  end

  test "format_log= stores the callable" do
    callable = lambda(&:to_json)
    UnifiedLogger.format_log = callable
    assert_same callable, UnifiedLogger.format_log_callable
  end

  test "format_log= raises DoubleDefineError on second assignment" do
    UnifiedLogger.format_log = -> {}
    assert_raises(UnifiedLogger::DoubleDefineError) { UnifiedLogger.format_log = -> {} }
  end

  test "format_log_callable is nil by default" do
    assert_nil UnifiedLogger.format_log_callable
  end

  # -- DoubleDefineError --

  test "DoubleDefineError is a StandardError" do
    assert UnifiedLogger::DoubleDefineError < StandardError
  end

  # -- Helper methods --

  test "backtrace_root returns Dir.pwd when Rails is not defined" do
    assert_equal Dir.pwd, UnifiedLogger.backtrace_root
  end

  test "current_logger returns nil when Rails is not defined" do
    assert_nil UnifiedLogger.current_logger
  end

  test "current_time returns a Time" do
    assert_kind_of Time, UnifiedLogger.current_time
  end

  # -- Delegation --

  test "trim delegates to Logger" do
    result = UnifiedLogger.trim({ name: "test" })
    assert_equal({ name: "test" }, result)
  end

  test "format delegates to Logger" do
    result = UnifiedLogger.format({ a: 1 })
    assert_equal({ "a" => 1 }, JSON.parse(result))
  end

  test "format_exception delegates to Logger" do
    result = UnifiedLogger.format_exception("boom")
    assert_equal({ message: "boom" }, result)
  end

  test "logs delegates to Logger" do
    UnifiedLogger::Logger.new($stdout).info("test")
    logs = UnifiedLogger.logs
    assert_equal 1, logs.size
    assert_equal :info, logs.first[:severity]
  end

  test "fetch_and_reset_logs delegates to Logger" do
    UnifiedLogger::Logger.new($stdout).info("test")
    logs = UnifiedLogger.fetch_and_reset_logs
    assert_equal 1, logs.size
    assert_empty UnifiedLogger.logs
  end

  test "reset_thread_logs delegates to Logger" do
    UnifiedLogger::Logger.new($stdout).info("test")
    UnifiedLogger.reset_thread_logs
    assert_empty UnifiedLogger.logs
  end

  # -- add / extra_log_fields delegation --

  test "add delegates to Logger" do
    UnifiedLogger.add(user_id: 1)
    assert_equal({ user_id: 1 }, UnifiedLogger::Logger.extra_log_fields)
  end

  test "extra_log_fields delegates to Logger" do
    UnifiedLogger::Logger.add(order_id: 42)
    assert_equal({ order_id: 42 }, UnifiedLogger.extra_log_fields)
  end

  test "fetch_and_reset_extra_log_fields delegates to Logger" do
    UnifiedLogger.add(user_id: 1)
    fields = UnifiedLogger.fetch_and_reset_extra_log_fields
    assert_equal({ user_id: 1 }, fields)
    assert_empty UnifiedLogger.extra_log_fields
  end
end
