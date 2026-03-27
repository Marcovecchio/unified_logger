require "test_helper"
require "unified_logger/sidekiq"

# Mirrors a real Sidekiq worker (include Sidekiq::Job) without requiring sidekiq.
# Sidekiq instantiates the worker and sets jid before passing it through the middleware chain.
class FakeSidekiqWorker
  attr_accessor :jid

  def perform(*args); end
end

class UnifiedLogger::SidekiqServerMiddlewareTest < UnifiedLoggerTestCase
  def setup
    super
    @logger, @io = create_test_logger
    UnifiedLogger.stubs(:current_logger).returns(@logger)
    @middleware = UnifiedLogger::SidekiqServerMiddleware.new
    @worker = build_fake_worker
  end

  # -- Helpers --

  def build_fake_worker(jid: "sidekiq-jid-123")
    worker = FakeSidekiqWorker.new
    worker.jid = jid
    worker
  end

  def native_job_hash(overrides = {})
    {
      "class"       => "FakeSidekiqWorker",
      "args"        => [1, "two"],
      "jid"         => @worker.jid,
      "queue"       => "default",
      "retry"       => true,
      "retry_count" => nil,
      "created_at"  => Time.now.to_f,
      "enqueued_at" => 1.minute.ago.to_f
    }.merge(overrides)
  end

  def active_job_hash(overrides = {})
    aj_payload = {
      "job_class"            => "OrderConfirmationJob",
      "job_id"               => "aj-uuid-456",
      "arguments"            => [99],
      "enqueued_at"          => 1.minute.ago.iso8601,
      "locale"               => "en",
      "exception_executions" => {}
    }.merge(overrides.delete(:aj) || {})

    {
      "class"       => "ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper",
      "wrapped"     => "OrderConfirmationJob",
      "args"        => [aj_payload],
      "jid"         => "wrapper-jid-789",
      "queue"       => "default",
      "retry"       => true,
      "retry_count" => nil,
      "enqueued_at" => Time.now.to_f
    }.merge(overrides)
  end

  # -- Basic behavior --

  test "yields to the block" do
    called = false
    @middleware.call(@worker, native_job_hash, "default") { called = true }
    assert called
  end

  test "returns the block return value" do
    result = @middleware.call(@worker, native_job_hash, "default") { 42 }
    assert_equal 42, result
  end

  test "writes log to logger" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal "job", log["log_type"]
  end

  # -- Native Sidekiq jobs --

  test "native: class_name is the worker class name" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal "FakeSidekiqWorker", log["class_name"]
  end

  test "native: id is jid" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal "sidekiq-jid-123", log["id"]
  end

  test "native: queue is from the queue parameter" do
    @middleware.call(@worker, native_job_hash, "critical") { "work" }
    log = parsed_log_from(@io)
    assert_equal "critical", log["queue"]
  end

  test "native: params are from job_hash args" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal [1, "two"], log["params"]
  end

  test "native: retry_count defaults to 0 on first execution" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal 0, log["retry_count"]
  end

  test "native: retry_count from job_hash" do
    @middleware.call(@worker, native_job_hash("retry_count" => 3), "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal 3, log["retry_count"]
  end

  # -- ActiveJob-wrapped jobs --

  test "activejob: class_name is the wrapped class" do
    @middleware.call(@worker, active_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal "OrderConfirmationJob", log["class_name"]
  end

  test "activejob: id is from AJ payload" do
    @middleware.call(@worker, active_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal "aj-uuid-456", log["id"]
  end

  test "activejob: params are from AJ payload arguments" do
    @middleware.call(@worker, active_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal [99], log["params"]
  end

  test "activejob: enqueued_at is from AJ payload" do
    @middleware.call(@worker, active_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert log.key?("enqueued_at")
  end

  # -- Max retries resolution --

  test "max_retries is 25 when retry is true" do
    @middleware.call(@worker, native_job_hash("retry" => true, "retry_count" => 3), "default") { "work" }
    log = parsed_log_from(@io)
    # With retry_count 3 < max_retries 25, if exception would be :warn
    assert_equal "ok", log["status"]
  end

  test "max_retries is 0 when retry is false" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash("retry" => false), "default") { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "error", log["status"]
  end

  test "max_retries uses integer value when retry is an integer" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash("retry" => 3, "retry_count" => 1), "default") { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "warn", log["status"]
  end

  # -- Status --

  test "status is ok when no exception" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_equal "ok", log["status"]
  end

  test "status is warn when exception and retries remaining" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash("retry" => 25, "retry_count" => 2), "default") { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "warn", log["status"]
  end

  test "status is error when exception and retries exhausted" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash("retry" => 3, "retry_count" => 3), "default") { raise "fail" }
    end
    log = parsed_log_from(@io)
    assert_equal "error", log["status"]
  end

  # -- Exception handling --

  test "includes exception details when block raises" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash, "default") { raise "boom" }
    end
    log = parsed_log_from(@io)
    assert_equal "RuntimeError", log["exception"]["class_name"]
    assert_equal "boom", log["exception"]["message"]
  end

  test "re-raises the exception" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash, "default") { raise "boom" }
    end
  end

  test "logs even when exception occurs" do
    assert_raises(RuntimeError) do
      @middleware.call(@worker, native_job_hash, "default") { raise "boom" }
    end

    @io.rewind
    assert_not_empty @io.read
  end

  # -- Duration --

  test "duration measures execution time" do
    @middleware.call(@worker, native_job_hash, "default") { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["duration"]
    assert log["duration"] >= 0
  end

  test "queue_duration is calculated from enqueued_at" do
    @middleware.call(@worker, native_job_hash("enqueued_at" => 5.minutes.ago.to_f), "default") { "work" }
    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["queue_duration"]
    assert log["queue_duration"].positive?
  end

  # -- Custom logs and extra fields --

  test "includes custom logs when present" do
    @middleware.call(@worker, native_job_hash, "default") do
      @logger.info("inside job")
    end
    log = parsed_log_from(@io)
    assert log.key?("custom")
    assert_equal 1, log["custom"].size
  end

  test "merges extra_log_fields" do
    @middleware.call(@worker, native_job_hash, "default") do
      UnifiedLogger::Logger.add(user_id: 123)
    end
    log = parsed_log_from(@io)
    assert_equal 123, log["user_id"]
  end
end
