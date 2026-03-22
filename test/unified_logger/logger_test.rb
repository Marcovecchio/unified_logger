require "test_helper"

class UnifiedLogger::LoggerTest < UnifiedLoggerTestCase
  def setup
    super
    @logger, @io = create_test_logger
  end

  # -- Initialization --

  test "initializes with a custom IO device" do
    assert_instance_of UnifiedLogger::Logger, @logger
  end

  test "formatter is set to a proc" do
    assert_instance_of Proc, @logger.formatter
  end

  # -- Severity methods --

  test "debug appends a custom log with debug severity" do
    @logger.debug("test message")
    assert_equal :debug, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "info appends a custom log with info severity" do
    @logger.info("test message")
    assert_equal :info, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "warn appends a custom log with warn severity" do
    @logger.warn("test message")
    assert_equal :warn, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "error appends a custom log with error severity" do
    @logger.error("test message")
    assert_equal :error, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "fatal appends a custom log with fatal severity" do
    @logger.fatal("test message")
    assert_equal :fatal, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "unknown appends a custom log with unknown severity" do
    @logger.unknown("test message")
    assert_equal :unknown, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "severity methods accept params hash" do
    @logger.info("msg", { user_id: 1 })
    assert_equal({ user_id: 1 }, UnifiedLogger::Logger.custom_logs.last[:params])
  end

  test "debug does not log when level is INFO" do
    @logger.level = ::Logger::INFO
    @logger.debug("should not appear")
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "info logs when level is INFO" do
    @logger.level = ::Logger::INFO
    @logger.info("should appear")
    assert_equal 1, UnifiedLogger::Logger.custom_logs.size
  end

  test "warn does not log when level is ERROR" do
    @logger.level = ::Logger::ERROR
    @logger.warn("should not appear")
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  # -- add method --

  test "add returns true for nil message" do
    assert_equal true, @logger.add(::Logger::INFO, nil)
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "add returns true for empty string message" do
    assert_equal true, @logger.add(::Logger::INFO, "")
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "add returns true when severity is below level" do
    @logger.level = ::Logger::ERROR
    assert_equal true, @logger.add(::Logger::DEBUG, "test")
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "add maps severity to correct symbol" do
    @logger.add(::Logger::WARN, "warning")
    assert_equal :warn, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "add maps unknown severity integer to :unknown" do
    @logger.add(999, "test")
    assert_equal :unknown, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  # -- << (shovel) operator --

  test "shovel appends log with unknown severity" do
    @logger << "message"
    assert_equal :unknown, UnifiedLogger::Logger.custom_logs.last[:severity]
  end

  test "shovel strips trailing newline" do
    @logger << "hello\n"
    assert_equal "hello", UnifiedLogger::Logger.custom_logs.last[:message]
  end

  test "shovel returns self for chaining" do
    assert_same @logger, (@logger << "x")
  end

  # -- write method --

  test "write sends message with newline to device" do
    @logger.write("hello")
    @io.rewind
    assert_equal "hello\n", @io.read
  end

  test "write does nothing if device does not respond to write" do
    logger, = create_test_logger
    logger.instance_variable_set(:@logging_device, :not_writable)
    assert_nothing_raised { logger.write("hello") }
  end

  # -- custom_logs (thread-local) --

  test "custom_logs returns empty array initially" do
    assert_equal [], UnifiedLogger::Logger.custom_logs
  end

  test "custom_logs is thread-local" do
    UnifiedLogger::Logger.append_custom_log(:info, "main thread", {})
    thread_logs = Thread.new { UnifiedLogger::Logger.custom_logs }.value
    assert_empty thread_logs
  end

  test "reset_thread_logs clears custom logs" do
    UnifiedLogger::Logger.append_custom_log(:info, "test", {})
    UnifiedLogger::Logger.reset_thread_logs
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "reset_thread_logs does not affect other threads" do
    other_thread_logs = nil
    t = Thread.new do
      UnifiedLogger::Logger.append_custom_log(:info, "other", {})
      sleep 0.1
      other_thread_logs = UnifiedLogger::Logger.custom_logs
    end
    sleep 0.05
    UnifiedLogger::Logger.reset_thread_logs
    t.join
    assert_equal 1, other_thread_logs.size
  end

  test "fetch_and_reset_custom_logs returns logs and clears" do
    UnifiedLogger::Logger.append_custom_log(:info, "one", {})
    UnifiedLogger::Logger.append_custom_log(:warn, "two", {})
    logs = UnifiedLogger::Logger.fetch_and_reset_custom_logs
    assert_equal 2, logs.size
    assert_empty UnifiedLogger::Logger.custom_logs
  end

  test "fetch_and_reset_custom_logs returns empty array when no logs" do
    assert_equal [], UnifiedLogger::Logger.fetch_and_reset_custom_logs
  end

  test "concurrent threads do not interfere" do
    threads = 5.times.map do |i|
      Thread.new do
        10.times { UnifiedLogger::Logger.append_custom_log(:info, "thread-#{i}", {}) }
        UnifiedLogger::Logger.custom_logs
      end
    end
    results = threads.map(&:value)
    results.each_with_index do |logs, i|
      assert_equal 10, logs.size
      logs.each { |log| assert_equal "thread-#{i}", log[:message] }
    end
  end

  # -- append_custom_log --

  test "appends hash with timestamp, severity, and message" do
    UnifiedLogger::Logger.append_custom_log(:info, "hello", {})
    log = UnifiedLogger::Logger.custom_logs.last
    assert log.key?(:timestamp)
    assert_equal :info, log[:severity]
    assert_equal "hello", log[:message]
  end

  test "omits blank params from the hash" do
    UnifiedLogger::Logger.append_custom_log(:info, "hello", {})
    log = UnifiedLogger::Logger.custom_logs.last
    refute log.key?(:params)
  end

  test "includes non-blank params" do
    UnifiedLogger::Logger.append_custom_log(:info, "hello", { user_id: 1 })
    log = UnifiedLogger::Logger.custom_logs.last
    assert_equal({ user_id: 1 }, log[:params])
  end

  test "cleans the message via clean_log_message" do
    UnifiedLogger::Logger.append_custom_log(:info, "\e[31mred\e[0m", {})
    assert_equal "red", UnifiedLogger::Logger.custom_logs.last[:message]
  end

  # -- clean_log_message --

  test "strips ANSI escape codes" do
    assert_equal "Error", UnifiedLogger::Logger.clean_log_message("\e[31mError\e[0m")
  end

  test "replaces double quotes with single quotes" do
    assert_equal "say 'hi'", UnifiedLogger::Logger.clean_log_message('say "hi"')
  end

  test "collapses multiple whitespace into single space" do
    assert_equal "a b", UnifiedLogger::Logger.clean_log_message("a   b")
  end

  test "strips leading and trailing whitespace" do
    assert_equal "hello", UnifiedLogger::Logger.clean_log_message("  hello  ")
  end

  test "returns non-string input unchanged" do
    assert_equal 123, UnifiedLogger::Logger.clean_log_message(123)
  end

  test "returns nil unchanged" do
    assert_nil UnifiedLogger::Logger.clean_log_message(nil)
  end

  # -- trim --

  test "returns small data as-is after filtering" do
    result = UnifiedLogger::Logger.trim({ name: "test" })
    assert_equal({ name: "test" }, result)
  end

  test "truncates data exceeding max_log_field_size" do
    UnifiedLogger.configure(max_log_field_size: 50)
    big_data = { content: "x" * 200 }
    result = UnifiedLogger::Logger.trim(big_data)
    assert_kind_of String, result
    assert_includes result, "extra characters omitted)"
  end

  test "filters data before trimming" do
    result = UnifiedLogger::Logger.trim({ password: "secret", name: "ok" })
    if result.is_a?(Hash)
      assert_equal "[FILTERED]", result[:password]
    else
      refute_includes result, "secret"
    end
  end

  test "handles JSON::GeneratorError gracefully" do
    UnifiedLogger.configure(max_log_field_size: 5)
    bad_string = "x" * 100
    bad_string.force_encoding("ASCII-8BIT")
    bad_string.define_singleton_method(:inspect) { "x" * 100 }
    result = UnifiedLogger::Logger.trim(bad_string)
    assert_kind_of String, result
  end

  # -- filter --

  test "filters password keys" do
    result = UnifiedLogger::Logger.filter({ password: "abc" })
    assert_equal "[FILTERED]", result[:password]
  end

  test "filters secret keys" do
    result = UnifiedLogger::Logger.filter({ secret: "xyz" })
    assert_equal "[FILTERED]", result[:secret]
  end

  test "filters token keys" do
    result = UnifiedLogger::Logger.filter({ token: "t" })
    assert_equal "[FILTERED]", result[:token]
  end

  test "does not filter non-sensitive keys" do
    result = UnifiedLogger::Logger.filter({ name: "Bob" })
    assert_equal "Bob", result[:name]
  end

  test "returns non-enumerable content unchanged" do
    assert_equal "plain string", UnifiedLogger::Logger.filter("plain string")
  end

  test "filter returns nil unchanged" do
    assert_nil UnifiedLogger::Logger.filter(nil)
  end

  test "filters nested hashes" do
    result = UnifiedLogger::Logger.filter({ user: { password: "x", name: "Bob" } })
    assert_equal "[FILTERED]", result[:user][:password]
    assert_equal "Bob", result[:user][:name]
  end

  # -- format --

  test "returns JSON string when no custom formatter" do
    result = UnifiedLogger::Logger.format({ a: 1 })
    assert_equal({ "a" => 1 }, JSON.parse(result))
  end

  test "calls custom log_transformer when present" do
    UnifiedLogger.log_transformer = ->(log) { "CUSTOM:#{log}" }
    result = UnifiedLogger::Logger.format({ a: 1 })
    assert result.start_with?("CUSTOM:")
  end

  test "filters the log before formatting" do
    result = UnifiedLogger::Logger.format({ password: "secret", name: "ok" })
    parsed = JSON.parse(result)
    assert_equal "[FILTERED]", parsed["password"]
    assert_equal "ok", parsed["name"]
  end

  # -- format_exception --

  test "formats a String exception as message hash" do
    assert_equal({ message: "boom" }, UnifiedLogger::Logger.format_exception("boom"))
  end

  test "formats an Exception with class_name, message, backtrace" do
    begin
      raise "fail"
    rescue StandardError => e
      result = UnifiedLogger::Logger.format_exception(e)
    end
    assert_equal "RuntimeError", result[:class_name]
    assert_equal "fail", result[:message]
    assert_kind_of Array, result[:backtrace]
  end

  test "cleans backtrace by removing prefix" do
    error = RuntimeError.new("fail")
    error.set_backtrace(["#{Dir.pwd}/app/foo.rb:1:in `bar'", "#{Dir.pwd}/app/baz.rb:2:in `qux'"])
    result = UnifiedLogger::Logger.format_exception(error)
    result[:backtrace].each do |line|
      refute line.start_with?(Dir.pwd)
    end
  end

  test "silences request_logger.rb from backtrace" do
    error = RuntimeError.new("fail")
    error.set_backtrace(["app/foo.rb:1", "lib/unified_logger/request_logger.rb:10", "app/bar.rb:2"])
    result = UnifiedLogger::Logger.format_exception(error)
    refute(result[:backtrace].any? { |line| line.include?("request_logger.rb") })
  end

  test "handles exception with nil backtrace" do
    error = RuntimeError.new("fail")
    result = UnifiedLogger::Logger.format_exception(error)
    assert_equal [], result[:backtrace]
  end

  test "formats object responding to to_s" do
    obj = Object.new
    obj.define_singleton_method(:to_s) { "custom_string" }
    assert_equal "custom_string", UnifiedLogger::Logger.format_exception(obj)
  end
end
