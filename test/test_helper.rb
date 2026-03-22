begin
  require "simplecov"
  SimpleCov.start do
    add_filter "/test/"
  end
rescue LoadError
  # simplecov not available on older Ruby versions
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "mocha/minitest"
require "stringio"
require "json"
require "logger"
require "rack"
require "active_support/all"
begin
  require "action_dispatch"
rescue LoadError
  # actionpack not available; filter tests will skip
end

require "unified_logger"

Time.zone = "UTC"

class UnifiedLoggerTestCase < ActiveSupport::TestCase
  def teardown
    UnifiedLogger.instance_variable_set(:@config, nil)
    UnifiedLogger.instance_variable_set(:@transform_request_log_callable, nil)
    UnifiedLogger.instance_variable_set(:@transform_job_log_callable, nil)
    UnifiedLogger.instance_variable_set(:@log_transformer, nil)
    UnifiedLogger::Logger.reset_thread_logs
  end

  private

  def create_test_logger
    io = StringIO.new
    logger = UnifiedLogger::Logger.new(io)
    [logger, io]
  end

  def build_rack_app(status: 200, headers: { "content-type" => "application/json" }, body: ['{"ok":true}'])
    ->(_env) { [status, headers, body] }
  end

  def build_rack_env(method: "GET", path: "/test", query_string: "", body: nil, content_type: nil, headers: {})
    env = Rack::MockRequest.env_for(
      query_string.empty? ? path : "#{path}?#{query_string}",
      method: method,
      input:  body
    )
    env["CONTENT_TYPE"] = content_type if content_type
    env["REQUEST_PATH"] = path
    env["action_dispatch.remote_ip"] = "127.0.0.1"
    env["action_dispatch.request_id"] = "test-request-id"
    headers.each { |k, v| env["HTTP_#{k.upcase.tr("-", "_")}"] = v }
    env
  end

  def build_fake_job(overrides = {})
    defaults = {
      job_id:               "abc-123",
      queue_name:           "default",
      arguments:            [1, "two"],
      executions:           0,
      exception_executions: {},
      enqueued_at:          1.minute.ago.iso8601,
      locale:               "en"
    }
    FakeJob.new(**defaults, **overrides)
  end

  def skip_unless_parameter_filter!
    skip "No ParameterFilter available" unless defined?(ActiveSupport::ParameterFilter) ||
                                               defined?(ActionDispatch::Http::ParameterFilter)
  end

  def parsed_log_from(io)
    io.rewind
    output = io.read
    JSON.parse(output.split("\n").last)
  end
end

class FakeJob
  attr_accessor :job_id, :queue_name, :arguments, :executions,
                :exception_executions, :enqueued_at, :locale

  def initialize(job_id:, queue_name:, arguments:, executions:, exception_executions:, enqueued_at:, locale:)
    @job_id = job_id
    @queue_name = queue_name
    @arguments = arguments
    @executions = executions
    @exception_executions = exception_executions
    @enqueued_at = enqueued_at
    @locale = locale
  end
end
