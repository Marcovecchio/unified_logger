module UnifiedLogger
  class Logger < ::Logger
    LOGS = Concurrent::ThreadLocalVar.new([])
    EXTRA_LOG_FIELDS = Concurrent::ThreadLocalVar.new({})
    SILENCED = Concurrent::ThreadLocalVar.new(false)
    SEVERITY_LEVELS = {
      debug:   ::Logger::DEBUG,
      info:    ::Logger::INFO,
      note:    ::Logger::Severity::NOTE,
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

    def debug(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::DEBUG, message)
    end

    def info(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::INFO, message)
    end

    def note(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::Severity::NOTE, message)
    end

    def warn(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::WARN, message)
    end

    def error(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::ERROR, message)
    end

    def fatal(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::FATAL, message)
    end

    def unknown(message = nil, &block)
      message = block.call if message.nil? && block
      add(::Logger::UNKNOWN, message)
    end

    def <<(message)
      add(::Logger::UNKNOWN, message.to_s.chomp)
      self
    end

    def write(message)
      @logging_device.write("#{message}\n") if @logging_device.respond_to?(:write)
    end

    class << self
      def logs
        LOGS.value
      end

      def silenced?
        SILENCED.value
      end

      def setup_silencing(path)
        SILENCED.value = UnifiedLogger.config[:silence_paths].any? do |pattern|
          pattern.is_a?(Regexp) ? pattern.match?(path) : pattern == path
        end
      end

      def add(hash)
        return if SILENCED.value

        EXTRA_LOG_FIELDS.value = EXTRA_LOG_FIELDS.value.merge(hash)
      end

      def extra_log_fields
        EXTRA_LOG_FIELDS.value
      end

      def reset_thread_logs
        LOGS.value = []
        EXTRA_LOG_FIELDS.value = {}
        SILENCED.value = false
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
        formatter = UnifiedLogger.format_log_callable
        formatter.present? ? formatter.call(filtered_log) : filtered_log.to_json
      end

      def write_log(log)
        logger = UnifiedLogger.current_logger
        max = UnifiedLogger.config[:max_log_size]
        if log.inspect.length <= max || !log.key?(:logs)
          logger.write(format(log))
        else
          entries = log.delete(:logs)
          logger.write(format(log))
          base_fields = log.except(:request, :response)
          write_overflow_logs(base_fields, entries, max, logger)
        end
      end

      private

      def write_overflow_logs(base_fields, entries, max, logger)
        part = 1
        group = []

        entries.each do |entry|
          candidate = group + [entry]
          overflow_log = base_fields.merge(overflow: part, logs: candidate)

          if overflow_log.inspect.length > max && group.any?
            logger.write(format(base_fields.merge(overflow: part, logs: group)))
            part += 1
            group = [entry]
          else
            group = candidate
          end
        end

        return if group.empty?

        logger.write(format(base_fields.merge(overflow: part, logs: group)))
      end

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

    def add(severity, message = nil, progname = nil, &block)
      if message.nil?
        message = block ? block.call : progname
      end

      return true if message.blank?
      return true unless severity >= level

      severity_symbol = SEVERITY_MAP[severity] || :unknown
      append_log(severity_symbol, message)
    end

    private

    def append_log(severity, message)
      return if SILENCED.value

      message = sanitize_log_message(message) if message.is_a?(String)
      log_hash = { timestamp: UnifiedLogger.formatted_time, severity: severity, message: message }

      LOGS.value = LOGS.value + [log_hash]
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
