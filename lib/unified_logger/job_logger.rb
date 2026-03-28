module UnifiedLogger
  class JobLogger
    class << self
      def log(class_name:, id: nil, queue: nil, params: nil,
              enqueued_at: nil, retry_count: 0, max_retries: nil, **extra)
        started = UnifiedLogger.current_time
        yield
      ensure
        if UnifiedLogger.current_logger.is_a?(UnifiedLogger::Logger)
          write_log(class_name: class_name, id: id, queue: queue, params: params,
                    enqueued_at: enqueued_at, retry_count: retry_count,
                    max_retries: max_retries, started: started, **extra)
        end
      end

      private

      def write_log(class_name:, id:, queue:, params:, enqueued_at:,
                    retry_count:, max_retries:, started:, **extra)
        enqueued_time = parse_time(enqueued_at)

        log = {
          log_type:       :job,
          timestamp:      UnifiedLogger.formatted_time,
          class_name:     class_name,
          id:             id,
          queue:          queue,
          params:         params,
          retry_count:    retry_count,
          enqueued_at:    enqueued_at,
          duration:       started ? UnifiedLogger.current_time - started : 0,
          queue_duration: enqueued_time && started ? started - enqueued_time : nil,
          thread_id:      Thread.current.object_id,
          process_id:     Process.pid
        }
        log.merge!(extra) if extra.any?
        log.compact!

        log[:custom] = Logger.fetch_and_reset_custom_logs if Logger.custom_logs.any?
        log.merge!(Logger.fetch_and_reset_extra_log_fields) if Logger.extra_log_fields.any?

        if $!
          log[:exception] = Logger.format_exception($!)
          log[:status] = max_retries && retry_count < max_retries ? :warn : :error
        else
          log[:status] = :ok
        end

        UnifiedLogger.transform_job_log_callable&.call(log)
        UnifiedLogger.current_logger.write(Logger.format(log))
      end

      def parse_time(value)
        case value
        when Numeric                           then Time.at(value).utc
        when String                            then Time.parse(value)
        when Time, ActiveSupport::TimeWithZone then value
        end
      end
    end
  end
end
