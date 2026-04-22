require "concurrent"
require "active_support/core_ext/object/blank"
require "active_support/core_ext/enumerable"
begin
  require "active_support/parameter_filter"
rescue LoadError
  # ActiveSupport < 6.0; falls back to ActionDispatch::Http::ParameterFilter at runtime
end
require "active_support/backtrace_cleaner"
require "json"
require "logger"

require_relative "unified_logger/version"
require_relative "unified_logger/severity"
require_relative "unified_logger/logger"
require_relative "unified_logger/request_logger"
require_relative "unified_logger/job_logger"

module UnifiedLogger
  class DoubleDefineError < StandardError; end

  DEFAULTS = {
    max_log_field_size:     2048,
    max_log_size:           10_000,
    filter_params:          %i[passw secret token crypt salt certificate otp ssn set-cookie http_authorization http_cookie pin],
    auto_insert_middleware: true,
    silence_paths:          []
  }.freeze

  def self.config
    @config ||= DEFAULTS.dup
  end

  def self.configure(options = {})
    config.merge!(options)
  end

  class << self
    attr_reader :transform_request_log_callable, :transform_job_log_callable, :format_log_callable

    def transform_request_log=(callable)
      raise DoubleDefineError, "transform_request_log already defined" if @transform_request_log_callable

      @transform_request_log_callable = callable
    end

    def transform_job_log=(callable)
      raise DoubleDefineError, "transform_job_log already defined" if @transform_job_log_callable

      @transform_job_log_callable = callable
    end

    def format_log=(callable)
      raise DoubleDefineError, "format_log already defined" if @format_log_callable

      @format_log_callable = callable
    end

    delegate :trim, :format, :format_exception,
             :logs, :reset_thread_logs,
             :add, :extra_log_fields,
             :silenced?, :setup_silencing,
             to: :"UnifiedLogger::Logger"
  end

  def self.backtrace_root
    if defined?(Rails)
      Rails.root.to_s
    else
      Dir.pwd
    end
  end

  def self.current_logger
    return unless defined?(Rails)

    return Rails.logger if Rails.logger.is_a?(UnifiedLogger::Logger)
    return Rails.logger unless Rails.logger.respond_to?(:broadcasts)

    Rails.logger.broadcasts.find { |l| l.is_a?(UnifiedLogger::Logger) } || Rails.logger
  end

  def self.current_time
    Time.zone&.now || Time.now.utc
  end

  def self.formatted_time
    current_time.iso8601(3)
  end
end

require "unified_logger/railtie" if defined?(Rails::Railtie)
