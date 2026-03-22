module UnifiedLogger
  class Railtie < Rails::Railtie
    initializer "unified_logger.middleware", after: :load_config_initializers do |app|
      app.middleware.insert_after ActionDispatch::DebugExceptions, UnifiedLogger::RequestLogger if UnifiedLogger.config[:auto_insert_middleware]
    end
  end
end
