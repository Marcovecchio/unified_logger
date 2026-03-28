require "unified_logger"

module UnifiedLogger
  class SidekiqServerMiddleware
    def call(job_instance, job_hash, queue, &)
      UnifiedLogger::JobLogger.log(**attrs_from(job_instance, job_hash, queue), &)
    end

    private

    def attrs_from(job_instance, job_hash, queue)
      aj = job_hash.key?("wrapped") ? job_hash.dig("args", 0) : nil
      retries = job_hash["retry"]

      {
        class_name:  aj&.[]("job_class") || job_hash["wrapped"] || job_instance.class.name,
        id:          aj&.[]("job_id") || job_hash["jid"],
        queue:       queue,
        params:      aj&.[]("arguments") || job_hash["args"],
        retry_count: job_hash["retry_count"].to_i,
        max_retries: resolve_max_retries(retries),
        enqueued_at: aj&.[]("enqueued_at") || job_hash["enqueued_at"]
      }.compact
    end

    def resolve_max_retries(retries)
      return retries if retries.is_a?(Integer)

      retries == false ? 0 : 25
    end
  end
end

if defined?(Sidekiq)
  Sidekiq.configure_server do |config|
    config.server_middleware do |chain|
      chain.add UnifiedLogger::SidekiqServerMiddleware
    end
  end
end
