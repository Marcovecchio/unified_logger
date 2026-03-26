module UnifiedLogger
  class JobLogger
    DEFAULT_MAX_RETRIES = 5

    class << self
      def log(job)
        yield
      ensure
        log_execution(job) if UnifiedLogger.current_logger.is_a?(UnifiedLogger::Logger)
      end

      private

      def log_execution(job)
        log = {
          log_type:             :job,
          timestamp:            UnifiedLogger.formatted_time,
          class_name:           job.class.name,
          id:                   job.job_id,
          queue:                job.queue_name,
          params:               job.arguments,
          executions_count:     job.executions,
          exception_executions: job.exception_executions,
          enqueued_at:          job.enqueued_at,
          locale:               job.locale,
          duration:             job.enqueued_at.present? ? UnifiedLogger.current_time - job.enqueued_at.in_time_zone : "unknown"
        }
        log[:custom] = UnifiedLogger::Logger.fetch_and_reset_custom_logs if UnifiedLogger::Logger.custom_logs.any?
        log.merge!(UnifiedLogger::Logger.fetch_and_reset_extra_log_fields) if UnifiedLogger::Logger.extra_log_fields.any?

        if $!
          log[:exception] = UnifiedLogger::Logger.format_exception($!)
          log[:status] = job.executions >= DEFAULT_MAX_RETRIES ? :error : :warn
        else
          log[:status] = :ok
        end

        UnifiedLogger.transform_job_log_callable&.call(log)
        UnifiedLogger.current_logger.write(UnifiedLogger::Logger.format(log))
      end
    end
  end
end
