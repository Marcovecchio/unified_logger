module UnifiedLogger
  class Logger < ::Logger
    CUSTOM_LOGS = Concurrent::ThreadLocalVar.new([])
    SEVERITY_LEVELS = {
      debug:   ::Logger::DEBUG,
      info:    ::Logger::INFO,
      warn:    ::Logger::WARN,
      error:   ::Logger::ERROR,
      fatal:   ::Logger::FATAL,
      unknown: ::Logger::UNKNOWN
    }.freeze
    SEVERITY_MAP = SEVERITY_LEVELS.invert.freeze

    def initialize(logging_device = $stdout, *)
      super
      @logging_device = logging_device
      self.formatter = proc {}
    end

    def debug(message = nil, params = {})
      add(::Logger::DEBUG, message, params)
    end

    def info(message = nil, params = {})
      add(::Logger::INFO, message, params)
    end

    def warn(message = nil, params = {})
      add(::Logger::WARN, message, params)
    end

    def error(message = nil, params = {})
      add(::Logger::ERROR, message, params)
    end

    def fatal(message = nil, params = {})
      add(::Logger::FATAL, message, params)
    end

    def unknown(message = nil, params = {})
      add(::Logger::UNKNOWN, message, params)
    end

    def <<(message)
      add(::Logger::UNKNOWN, message.to_s.chomp, {})
      self
    end

    def write(message)
      @logging_device.write("#{message}\n") if @logging_device.respond_to?(:write)
    end

    class << self
      def custom_logs
        CUSTOM_LOGS.value
      end

      def reset_thread_logs
        CUSTOM_LOGS.value = []
      end

      def fetch_and_reset_custom_logs
        logs = custom_logs
        reset_thread_logs
        logs
      end

      def trim(data)
        data = filter(data)
        size = data.inspect.length
        max = UnifiedLogger.config[:max_log_field_size]
        return data if size < max

        begin
          json = JSON.generate(data, quirks_mode: true)
        rescue JSON::GeneratorError, Encoding::UndefinedConversionError
          json = data.respond_to?("to_s") ? data.to_s : "unparseable object (instance of #{data.class.name})"
        end
        "#{json[0..max]}... (#{size - max} extra characters omitted)"
      end

      def format_exception(exception)
        if exception.is_a?(String)
          { message: exception }
        elsif exception.is_a?(Exception)
          btc = ActiveSupport::BacktraceCleaner.new
          prefix = UnifiedLogger.backtrace_root + File::SEPARATOR
          btc.add_filter { |line| line.sub(/\A#{Regexp.escape(prefix)}/, "") }
          btc.add_silencer { |line| /request_logger.rb/.match?(line) }
          { class_name: exception.class.name, message: exception.message, backtrace: btc.clean(exception.backtrace || []) }
        elsif exception.respond_to?(:to_s)
          exception.to_s
        else
          exception.class.name
        end
      end

      def format(log)
        filtered_log = filter(log)
        formatter = UnifiedLogger.log_transformer
        formatter.present? ? formatter.call(filtered_log) : filtered_log.to_json
      end

      private

      def filter(content)
        return content unless content.respond_to?(:each)

        filter_class = if defined?(ActiveSupport::ParameterFilter)
                         ActiveSupport::ParameterFilter
                       elsif defined?(ActionDispatch::Http::ParameterFilter)
                         ActionDispatch::Http::ParameterFilter
                       end
        return content unless filter_class

        filter_class.new(UnifiedLogger.config[:filter_params]).filter(content)
      end
    end

    private

    def add(severity, message = nil, params = {})
      return true if message.blank?
      return true unless severity >= level

      severity_symbol = SEVERITY_MAP[severity] || :unknown
      append_custom_log(severity_symbol, message, params)
    end

    def append_custom_log(severity, message, params)
      clean_message = sanitize_log_message(message)
      log_hash = { timestamp: UnifiedLogger.current_time, severity: severity,
                   message: clean_message, params: params }.reject { |_, v| v.respond_to?(:empty?) ? v.empty? : !v }

      CUSTOM_LOGS.value = CUSTOM_LOGS.value + [log_hash]
    end

    def sanitize_log_message(text)
      return text unless text.is_a?(String)

      text = text.gsub(/\e\[[0-9;]*m/, "")
      text = text.gsub(%r{[^a-zA-Z0-9\s.,;:!?'"()\[\]{}\-_@#$%&*+=<>|~`/]}, "")
      text = text.gsub('"', "'")
      text = text.gsub(/\s+/, " ")
      text.strip
    end
  end
end
