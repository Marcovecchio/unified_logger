module UnifiedLogger
  class RequestLogger
    def initialize(app)
      @app = app
    end

    def call(env)
      return @app.call(env) unless UnifiedLogger.current_logger.is_a?(UnifiedLogger::Logger)

      UnifiedLogger::Logger.reset_thread_logs
      UnifiedLogger.setup_silencing(env["REQUEST_PATH"])
      started = UnifiedLogger.current_time
      status, headers, response = @app.call(env)
    ensure
      if UnifiedLogger.current_logger.is_a?(UnifiedLogger::Logger) && !UnifiedLogger.silenced?
        log = build_log(started, env, status, headers, response)
        UnifiedLogger.transform_request_log_callable&.call(log, env)
        UnifiedLogger::Logger.write_log(log)
      end
    end

    private

    def build_log(started, env, status = nil, headers = nil, response = nil)
      status   ||= 500
      headers  ||= {}
      response ||= ""
      path_parameters = env["action_dispatch.request.path_parameters"] || {}
      query_string = env["QUERY_STRING"]
      log = {
        log_type:   :request,
        timestamp:  UnifiedLogger.formatted_time,
        id:         env["action_dispatch.request_id"],
        ip:         env["action_dispatch.remote_ip"].to_s,
        controller: path_parameters[:controller]&.camelize&.concat("Controller"),
        action:     path_parameters[:action],
        request:    {
          path:         env["REQUEST_PATH"],
          method:       env["REQUEST_METHOD"],
          headers:      env.select { |e| e.start_with?("HTTP_") }.reject { |h| h.start_with?("HTTP_SEC_") },
          path_params:  path_parameters.except(:controller, :action),
          query_params: query_string.blank? ? {} : Rack::Utils.parse_nested_query(query_string),
          body:         request_body(env)
        },
        response:   {
          headers: headers,
          status:  status,
          body:    response_body(response, headers["content-type"])
        },
        thread_id:  Thread.current.object_id,
        process_id: Process.pid,
        duration:   started ? UnifiedLogger.current_time - started : 0
      }
      log[:exception] = UnifiedLogger::Logger.format_exception($!) if $!.present?
      log[:logs] = UnifiedLogger::Logger.logs if UnifiedLogger::Logger.logs.any?
      log.merge!(UnifiedLogger::Logger.extra_log_fields) if UnifiedLogger::Logger.extra_log_fields.any?

      log
    end

    def request_body(env)
      return nil unless (input = env["rack.input"])
      return env["rack.request.form_hash"] if env["rack.request.form_hash"]

      input.rewind
      body = input.read
      input.rewind

      parse_body(body, env["CONTENT_TYPE"])
    end

    def response_body(response, content_type)
      return nil if response.nil? || (response.respond_to?(:empty?) && response.empty?)
      return nil if content_type&.exclude?("application/") && content_type.exclude?("text/plain")
      return response_body(response.body, content_type) if response.respond_to?(:body)

      body = response.respond_to?(:map) ? response.join : response.to_s

      parse_body(body, content_type)
    ensure
      response.close if response.respond_to?(:close)
    end

    def parse_body(body, content_type)
      return nil if body.nil?
      return nil if body.empty?

      main_content_type = content_type&.split(";")&.first&.strip&.downcase

      case main_content_type
      when "application/json"
        JSON.parse(body)
      when "application/x-www-form-urlencoded"
        Rack::Utils.parse_nested_query(body)
      else
        UnifiedLogger::Logger.trim(body)
      end
    rescue JSON::ParserError, TypeError, ArgumentError
      body
    end
  end
end
