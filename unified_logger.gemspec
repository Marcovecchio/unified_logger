require_relative "lib/unified_logger/version"

Gem::Specification.new do |spec|
  spec.name          = "unified_logger"
  spec.version       = UnifiedLogger::VERSION
  spec.authors       = ["Marcovecchio"]
  spec.summary       = "Structured JSON logging for Rack and Rails applications"
  spec.description   = "One JSON log line per request or job. Captures request/response data, in-app logger calls, " \
                        "exceptions with cleaned backtraces, and sensitive data filtering — all in a single event."
  spec.homepage      = "https://github.com/marcovecchio/unified_logger"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 2.4"

  spec.add_dependency "activesupport", ">= 4.2", "< 9"
  spec.add_dependency "concurrent-ruby", "~> 1.0"
  spec.add_dependency "rack", ">= 1.6", "< 4"

  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["source_code_uri"]       = "https://github.com/marcovecchio/unified_logger"
end
