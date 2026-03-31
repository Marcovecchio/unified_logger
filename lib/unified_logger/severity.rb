# frozen_string_literal: true

# Extends Ruby's Logger::Severity to recognize the custom :note level (1.5),
# sitting between INFO (1) and WARN (2). This patch ensures ALL logger instances
# (not just UnifiedLogger::Logger) accept :note as a valid level — which is
# required because Rails applies config.log_level to every logger it creates.

module UnifiedLoggerSeverity
  CUSTOM_LEVELS = { "note" => 1.5 }.freeze

  def coerce(severity)
    if severity.is_a?(Numeric)
      severity
    else
      key = severity.to_s.downcase
      CUSTOM_LEVELS[key] || super
    end
  end
end

Logger::Severity.singleton_class.prepend(UnifiedLoggerSeverity)
Logger::Severity.const_set(:NOTE, 1.5) unless Logger::Severity.const_defined?(:NOTE)
