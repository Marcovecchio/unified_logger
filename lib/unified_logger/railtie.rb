# frozen_string_literal: true

module UnifiedLogger
  class Railtie < Rails::Railtie
    initializer "unified_logger.middleware", after: :load_config_initializers do |app|
      if UnifiedLogger.config[:auto_insert_middleware]
        app.middleware.insert_after ActionDispatch::DebugExceptions,
                                    UnifiedLogger::RequestLogger
      end
    end
  end
end
