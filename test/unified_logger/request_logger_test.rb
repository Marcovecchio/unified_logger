require "test_helper"

class UnifiedLogger::RequestLoggerTest < UnifiedLoggerTestCase
  def setup
    super
    @logger, @io = create_test_logger
    UnifiedLogger.stubs(:current_logger).returns(@logger)
  end

  # -- Pass-through --

  test "passes through without logging when current_logger is not UnifiedLogger::Logger" do
    UnifiedLogger.stubs(:current_logger).returns(::Logger.new(StringIO.new))
    app = build_rack_app
    middleware = UnifiedLogger::RequestLogger.new(app)
    env = build_rack_env

    status, = middleware.call(env)

    assert_equal 200, status
    @io.rewind
    assert_empty @io.read
  end

  # -- Basic request logging --

  test "writes a JSON log line after request" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal "request", log["log_type"]
  end

  test "log includes request path" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(path: "/api/users"))

    log = parsed_log_from(@io)
    assert_equal "/api/users", log["request"]["path"]
  end

  test "log includes request method" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(method: "POST"))

    log = parsed_log_from(@io)
    assert_equal "POST", log["request"]["method"]
  end

  test "log includes response status" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app(status: 201))
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal 201, log["response"]["status"]
  end

  test "log includes response headers" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_kind_of Hash, log["response"]["headers"]
  end

  test "log includes thread_id and process_id" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert log.key?("thread_id")
    assert log.key?("process_id")
  end

  test "log includes duration as a number" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_kind_of Numeric, log["duration"]
  end

  test "log includes request_id and ip" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal "test-request-id", log["id"]
    assert_equal "127.0.0.1", log["ip"]
  end

  # -- Request body parsing --

  test "parses JSON request body" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    env = build_rack_env(
      method:       "POST",
      body:         '{"name":"test"}',
      content_type: "application/json"
    )
    middleware.call(env)

    log = parsed_log_from(@io)
    assert_equal({ "name" => "test" }, log["request"]["body"])
  end

  test "parses form-encoded request body" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    env = build_rack_env(
      method:       "POST",
      body:         "name=test&age=25",
      content_type: "application/x-www-form-urlencoded"
    )
    middleware.call(env)

    log = parsed_log_from(@io)
    assert_equal "test", log["request"]["body"]["name"]
  end

  test "trims non-JSON non-form request body" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    env = build_rack_env(
      method:       "POST",
      body:         "plain text body",
      content_type: "text/plain"
    )
    middleware.call(env)

    log = parsed_log_from(@io)
    assert_kind_of String, log["request"]["body"]
  end

  test "uses form_hash when present in env" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    env = build_rack_env(method: "POST", body: "ignored", content_type: "application/x-www-form-urlencoded")
    env["rack.request.form_hash"] = { "from_form" => "yes" }
    middleware.call(env)

    log = parsed_log_from(@io)
    assert_equal({ "from_form" => "yes" }, log["request"]["body"])
  end

  # -- Response body parsing --

  test "parses JSON response body" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app(body: ['{"result":"ok"}']))
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal({ "result" => "ok" }, log["response"]["body"])
  end

  test "returns nil for non-application content types" do
    middleware = UnifiedLogger::RequestLogger.new(
      build_rack_app(headers: { "content-type" => "text/html" }, body: ["<html></html>"])
    )
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_nil log["response"]["body"]
  end

  test "allows text/plain response through" do
    middleware = UnifiedLogger::RequestLogger.new(
      build_rack_app(headers: { "content-type" => "text/plain" }, body: ["hello"])
    )
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal "hello", log["response"]["body"]
  end

  test "returns nil for empty response body" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app(body: [""]))
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_nil log["response"]["body"]
  end

  test "handles invalid JSON in response gracefully" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app(body: ["not{json"]))
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal "not{json", log["response"]["body"]
  end

  # -- Silenced paths --

  test "does not log when path matches a string in silence_paths" do
    UnifiedLogger.configure(silence_paths: ["/health"])
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(path: "/health"))

    @io.rewind
    assert_empty @io.read
  end

  test "does not log when path matches a Regexp in silence_paths" do
    UnifiedLogger.configure(silence_paths: [%r{^/up}])
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(path: "/up"))

    @io.rewind
    assert_empty @io.read
  end

  test "logs normally when path does not match silence_paths" do
    UnifiedLogger.configure(silence_paths: ["/health"])
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(path: "/api/users"))

    log = parsed_log_from(@io)
    assert_equal "request", log["log_type"]
  end

  # -- Exception handling --

  test "logs exception info when inner app raises" do
    app = ->(_env) { raise "boom" }
    middleware = UnifiedLogger::RequestLogger.new(app)

    assert_raises(RuntimeError) { middleware.call(build_rack_env) }

    log = parsed_log_from(@io)
    assert_equal "RuntimeError", log["exception"]["class_name"]
    assert_equal "boom", log["exception"]["message"]
  end

  test "defaults status to 500 when app raises" do
    app = ->(_env) { raise "boom" }
    middleware = UnifiedLogger::RequestLogger.new(app)

    assert_raises(RuntimeError) { middleware.call(build_rack_env) }

    log = parsed_log_from(@io)
    assert_equal 500, log["response"]["status"]
  end

  # -- Custom logs integration --

  test "includes custom logs when present" do
    app = lambda do |_env|
      @logger.info("inside request")
      [200, { "content-type" => "application/json" }, ['{"ok":true}']]
    end
    middleware = UnifiedLogger::RequestLogger.new(app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert log.key?("custom")
    assert_equal 1, log["custom"].size
  end

  test "resets custom logs after request" do
    app = lambda do |_env|
      @logger.info("inside")
      [200, { "content-type" => "application/json" }, ['{"ok":true}']]
    end
    middleware = UnifiedLogger::RequestLogger.new(app)
    middleware.call(build_rack_env)

    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "omits custom key when no custom logs" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_not log.key?("custom")
  end

  # -- Transform request log callable --

  test "calls transform_request_log_callable and merges result" do
    UnifiedLogger.transform_request_log = ->(custom, _env) { custom[:extra_field] = "hello" }
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal "hello", log["extra_field"]
  end

  test "works when transform_request_log_callable is nil" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    assert_nothing_raised { middleware.call(build_rack_env) }
  end

  # -- Query string parsing --

  test "parses query string into query_params" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(query_string: "foo=bar&baz=1"))

    log = parsed_log_from(@io)
    assert_equal "bar", log["request"]["query_params"]["foo"]
    assert_equal "1", log["request"]["query_params"]["baz"]
  end

  test "query_params is empty hash when no query string" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env)

    log = parsed_log_from(@io)
    assert_equal({}, log["request"]["query_params"])
  end

  # -- Headers filtering --

  test "includes HTTP_ headers in request log" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    middleware.call(build_rack_env(headers: { "Accept" => "application/json" }))

    log = parsed_log_from(@io)
    assert log["request"]["headers"].key?("HTTP_ACCEPT")
  end

  test "excludes HTTP_SEC_ headers from request log" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    env = build_rack_env
    env["HTTP_SEC_FETCH_MODE"] = "navigate"
    middleware.call(env)

    log = parsed_log_from(@io)
    assert_not log["request"]["headers"].key?("HTTP_SEC_FETCH_MODE")
  end

  # -- Path parameters --

  test "extracts controller and action from path_parameters" do
    middleware = UnifiedLogger::RequestLogger.new(build_rack_app)
    env = build_rack_env
    env["action_dispatch.request.path_parameters"] = { controller: "users", action: "index", id: "1" }
    middleware.call(env)

    log = parsed_log_from(@io)
    assert_equal "users", log["controller"]
    assert_equal "index", log["action"]
    assert_equal "1", log["request"]["path_params"]["id"]
  end
end
