# UnifiedLogger

[![Gem Version](https://img.shields.io/gem/v/unified_logger)](https://rubygems.org/gems/unified_logger)
[![CI](https://github.com/marcovecchio/unified_logger/actions/workflows/ci.yml/badge.svg)](https://github.com/marcovecchio/unified_logger/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Structured JSON logging for Ruby Rack and Rails applications. One log line per request. One log line per job. Everything you need, at the right place.

---

## The Problem

Rails default logging is noisy and unstructured:

- A single HTTP request produces **multiple log lines** spread across the output — started, parameters, rendered, completed — making it painful to correlate in log aggregators like Datadog, Elasticsearch, or CloudWatch.
- **Background job logs are disconnected** from the request that enqueued them, with no structured metadata about retries, duration, or failure status.
- In-app `Rails.logger` calls (e.g., `Rails.logger.info("Payment processed")`) are **written as standalone lines** that float away from the request or job that triggered them.
- **Sensitive data** (passwords, tokens, cookies) can leak into logs unless you manually configure filtering everywhere.
- Multi-threaded servers like Puma **interleave log lines** from concurrent requests, making debugging nearly impossible.
- **Error backtraces are noisy and disconnected** — when something breaks, Rails dumps a multi-line backtrace full of framework noise, scattered across the log output with no link to the request that caused it. You typically need a dedicated error tracking service like Sentry or Airbrake just to make sense of failures.

## The Solution

UnifiedLogger replaces this chaos with a single, structured JSON line per event:

- **One line per request** — path, method, headers, params, body, response status, response body, duration, thread/process IDs, and any exceptions, all in one JSON object.
- **One line per job** — class name, queue, arguments, retry count, duration, status (`:ok`, `:warn`, `:error`), and any exceptions.
- **In-app logs are captured** — every `Rails.logger.info(...)` call during a request or job is collected in a thread-safe buffer and included in that event's log line under the `custom` key.
- **Sensitive data is filtered** out of the box — passwords, tokens, secrets, cookies, and more are replaced with `[FILTERED]`.
- **Exceptions with cleaned backtraces** — when a request or job raises, the exception details (class, message, and a cleaned backtrace with framework noise stripped out) are captured and included in the log entry. It's done without disturbing the exception or changing how it's handled.
- **Log transform hooks** let you add tenant IDs, Datadog correlation, deploy versions, or anything else to every log line.

---

## Quick Start

Add to your Gemfile:

```ruby
gem "unified_logger"
```

```bash
bundle install
```

Set your Rails logger:

```ruby
# config/environments/production.rb (and/or any other environment)
config.logger = UnifiedLogger::Logger.new($stdout)
config.logger.level = :info
```

That's it. The middleware auto-inserts itself, and every request now produces a single structured JSON log line.

---

## Configuration

All configuration is optional. UnifiedLogger ships with sensible defaults.

```ruby
# config/initializers/unified_logger.rb
UnifiedLogger.configure(
  max_log_field_size:     2048,                              # truncate fields larger than this (default: 2048)
  filter_params:          %i[passw secret token],            # sensitive param patterns (default: see below)
  auto_insert_middleware: true,                               # auto-insert Rack middleware in Rails (default: true)
  silence_paths:          ["/health", %r{^/assets/}]         # paths to skip logging (default: [])
)
```

### Options

| Option | Default | Description |
|---|---|---|
| `max_log_field_size` | `2048` | Maximum character length for any single log field. Larger values are truncated with a `"... (N extra characters omitted)"` suffix. |
| `filter_params` | See below | Array of symbols matching sensitive parameter names. Uses pattern matching — `:passw` matches `password`, `password_confirmation`, etc. |
| `auto_insert_middleware` | `true` | Automatically insert `UnifiedLogger::RequestLogger` into the Rails middleware stack. Set to `false` if you need to control middleware order manually. |
| `silence_paths` | `[]` | Array of strings or regexps. Requests matching these paths are not logged. Useful for health checks, assets, etc. |

### Default Filtered Parameters

```ruby
%i[passw secret token crypt salt certificate otp ssn set-cookie http_authorization http_cookie pin]
```

To add your own on top of the defaults:

```ruby
UnifiedLogger.configure(
  filter_params: UnifiedLogger::DEFAULTS[:filter_params] + %i[credit_card cpf]
)
```

---

## Full Initializer Example

Here is a complete initializer showcasing all customization features. Copy it to `config/initializers/unified_logger.rb` and uncomment what you need:

```ruby
UnifiedLogger.configure(
  # If set to false, you need to manually add the middleware
  # auto_insert_middleware: true,

  # Paths to silence in request logs
  # silence_paths: [%r{^/assets/}, "/up", "/status", "/health-check"],

  # Add additional parameters to filter out from logs
  # filter_params: UnifiedLogger::DEFAULTS[:filter_params] + %i[password]
)

def transform_log(log, env = nil)
  # Round duration for readability
  log[:duration] = log[:duration].round(4) if log[:duration].is_a?(Numeric)

  # Strip verbose fields and simplify custom log entries in development, for cleaner logs
  # if Rails.env.development?
  #   log[:request]&.delete(:headers)
  #   log[:response]&.delete(:headers)
  #   log.delete(:id)
  #   log.delete(:ip)
  #   log.delete(:thread_id)
  #   log.delete(:process_id)
  #   log[:custom] = log[:custom].map { |entry| entry[:message] } if log[:custom].is_a?(Array)
  # end

  # Example of adding Datadog correlation info if Datadog tracing is available.
  # You can customize this to include any additional info your logging system supports or needs.
  # if defined?(Datadog::Tracing)
  #   correlation = Datadog::Tracing.correlation
  #   log[:dd] = {
  #     trace_id: correlation.trace_id.to_s,
  #     span_id:  correlation.span_id.to_s,
  #     env:      correlation.env.to_s,
  #     service:  correlation.service.to_s,
  #     version:  correlation.version.to_s
  #   }
  # end

  # Since this method transforms logs for both requests and jobs, we need this guard clause,
  # because jobs have no env object, and we will need it from now on.
  return unless env.present?

  # Example of adding custom authentication info from the Rack environment
  # log[:authentication] = env["authentication"]

  # Example of adding custom request info from the Rack environment
  # req = Rack::Request.new(env)
  # log[:extra_log_field] = req.extra_log_field if req.respond_to?(:extra_log_field)
end

def format_log(log)
  # Controls the final output format. Receives the filtered log hash, must return a string. Default (when not set) is JSON.
  if Rails.env.development?
    require "pp"
    formatted = ""
    if log[:log_type] != :job
      formatted += "#{log.dig(:request, :method)} #{log.dig(:request, :path)} (#{log[:duration]}s)\n"
    end
    formatted + log.pretty_inspect + "---------------------------------------------------------"
  else
    log.to_json
  end
end

# Set the transform_log method to request and job configuration options in UnifiedLogger.
# In this case, a single method handles both.
UnifiedLogger.transform_request_log = method(:transform_log)
UnifiedLogger.transform_job_log = method(:transform_log)

# Do the same for format_log method.
UnifiedLogger.format_log = method(:format_log)
```

### What this does

- **`transform_log`** — Receives the full log hash and (for requests) the Rack `env`. For jobs, `env`will be `nil`. You can add, modify, or delete any fields in-place — changes are applied directly since Ruby hashes are passed by reference.
- **`format_log`** — Controls the final output format. Receives the filtered log hash and must return a string. When not set, the default is JSON. The example above shows a common pattern: human-readable pretty-printed output in development, and compact JSON in production.
- **Wiring** — The last three lines assign these methods to UnifiedLogger's hooks. Each hook can only be assigned once (raises `DoubleDefineError` on reassignment), so set them in a single initializer.

### Adding custom fields from controllers

Use `UnifiedLogger.add` to merge fields directly into the current request or job log. It accepts a Hash with any internal structure:

```ruby
class OrdersController < ApplicationController
  def create
    order = Order.create!(order_params)
    UnifiedLogger.add(order_id: order.id, user_id: current_user.id)
  end
end
```

The fields are stored in thread-local storage (like `custom_logs`), so they are per-request and thread-safe. When the request finishes, they are merged into the main log hash:

```json
{ "log_type": "request", "...", "order_id": 123, "user_id": 456 }
```

You can call `add` multiple times — each call merges into the same hash. This works in both requests and jobs.

---

## Usage

### Rails (Automatic)

With `auto_insert_middleware: true` (the default), the `RequestLogger` middleware is automatically inserted into the Rails middleware stack after `ActionDispatch::DebugExceptions` via a Railtie. Just set the logger:

```ruby
# config/environments/production.rb
config.logger = UnifiedLogger::Logger.new($stdout)
config.logger.level = :info
```

### Rack (Manual)

For non-Rails Rack apps, add the middleware manually:

```ruby
# config.ru
require "unified_logger"

use UnifiedLogger::RequestLogger
run MyApp
```

### Background Jobs

`JobLogger.log` works with any job engine — ActiveJob, Sidekiq, GoodJob, Que, or anything else. Pass job attributes as keyword arguments:

```ruby
UnifiedLogger::JobLogger.log(
  class_name: "OrderConfirmationJob",
  id:         job_id,
  queue:      queue_name,
  params:     arguments,
  retry_count: retry_attempt,
  max_retries: max_allowed,
  enqueued_at: enqueued_timestamp
) { perform_the_job }
```

`class_name` is the only required argument. All others are optional.

#### ActiveJob

```ruby
class ApplicationJob < ActiveJob::Base
  around_perform do |job, block|
    UnifiedLogger::JobLogger.log(
      class_name:           job.class.name,
      id:                   job.job_id,
      queue:                job.queue_name,
      params:               job.arguments,
      retry_count:          job.executions,
      enqueued_at:          job.enqueued_at,
      locale:               job.locale,
      exception_executions: job.exception_executions
    ) { block.call }
  end
end
```

#### Sidekiq

For Sidekiq (native workers or as an ActiveJob backend), add a single require:

```ruby
# config/initializers/sidekiq.rb
require "unified_logger/sidekiq"
```

This auto-registers a Sidekiq server middleware that logs all job executions — both native `Sidekiq::Job` workers and ActiveJob-wrapped jobs. No `around_perform` hook needed.

**Note:** The `unified_logger` gem does not depend on `sidekiq`. The middleware is loaded only when you explicitly require it.

Every job produces a single log line with class name, queue, arguments, retry count, duration, queue duration, and status.

### In-App Logging

Use standard logger methods anywhere in your code:

```ruby
Rails.logger.info("Payment processed")
Rails.logger.info(message: "Payment processed", amount: 100, currency: "BRL")
Rails.logger.warn("Rate limit approaching")
Rails.logger.error(service: "stripe", status: 502, message: "External API failed")
```

The message can be a String, Hash, or Array — it is stored as-is and serialized to JSON. These calls are **not written immediately**. They are collected in a thread-safe buffer and included in the `custom` key of the enclosing request or job log line. This keeps all related information in a single event.

---

## Log Output

### Request Log

Each HTTP request produces a single JSON line. All timestamps use **ISO 8601 with millisecond precision** (`2026-03-22T14:30:00.123Z`):

```json
{
  "log_type": "request",
  "timestamp": "2026-03-22T14:30:00.123Z",
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "ip": "192.168.1.1",
  "controller": "orders",
  "action": "create",
  "request": {
    "path": "/orders",
    "method": "POST",
    "headers": {
      "HTTP_ACCEPT": "application/json",
      "HTTP_AUTHORIZATION": "[FILTERED]"
    },
    "path_params": {},
    "query_params": {},
    "body": {
      "order": {
        "item_id": 42,
        "password": "[FILTERED]"
      }
    }
  },
  "response": {
    "headers": { "content-type": "application/json; charset=utf-8" },
    "status": 201,
    "body": { "id": 99, "status": "pending" }
  },
  "thread_id": 70368818150320,
  "process_id": 12345,
  "duration": 0.0423,
  "custom": [
    {
      "timestamp": "2026-03-22T14:30:00.000Z",
      "severity": "info",
      "message": { "message": "Payment processed", "amount": 100, "currency": "BRL" }
    }
  ]
}
```

### Job Log

Each background job produces a single JSON line:

```json
{
  "log_type": "job",
  "timestamp": "2026-03-22T14:30:01.456Z",
  "class_name": "OrderConfirmationJob",
  "id": "f8e7d6c5-b4a3-2190-fedc-ba0987654321",
  "queue": "default",
  "params": [99],
  "retry_count": 0,
  "enqueued_at": "2026-03-22T14:30:00.000Z",
  "duration": 0.234,
  "queue_duration": 1.456,
  "thread_id": 70368818150320,
  "process_id": 12345,
  "status": "ok",
  "custom": [
    {
      "timestamp": "2026-03-22T14:30:01.789Z",
      "severity": "info",
      "message": "Order confirmation email sent"
    }
  ]
}
```

- `duration` — how long the job took to execute.
- `queue_duration` — time from enqueue to execution start (only present when `enqueued_at` is provided).
- Extra kwargs (like `locale`, `exception_executions`) are merged into the log as top-level keys.

When a job fails and `max_retries` is provided with retries remaining, `status` is `"warn"`. When retries are exhausted or `max_retries` is not provided, `status` is `"error"` and an `exception` key is included with `class_name`, `message`, and a cleaned `backtrace`.

### Exception with Backtrace

When a request or job raises an exception, UnifiedLogger observes it without interfering. There is no rescue and no re-raise — the logging runs in an `ensure` block and reads `$ERROR_INFO` (`$!`), so the exception propagates exactly as it would without UnifiedLogger present. The `exception` key includes the class name, message, and a **cleaned backtrace** with framework noise stripped out, so you only see your application code:

```json
{
  "log_type": "request",
  "controller": "payments",
  "action": "create",
  "request": { "path": "/payments", "method": "POST" },
  "response": { "status": 500 },
  "duration": 0.0091,
  "exception": {
    "class_name": "ActiveRecord::RecordNotFound",
    "message": "Couldn't find Order with 'id'=999",
    "backtrace": [
      "app/models/order.rb:12:in `find_or_fail'",
      "app/services/payment_service.rb:45:in `process'",
      "app/controllers/payments_controller.rb:8:in `create'"
    ]
  }
}
```

The backtrace is cleaned using `ActiveSupport::BacktraceCleaner`: the project root prefix is removed from each frame, and internal middleware lines are silenced. This gives you a concise, readable stack trace pointing directly at the relevant lines in your code.

---

## Under the Hood

### Request Lifecycle

```
                         ┌─────────────────────────────────┐
    HTTP Request         │     RequestLogger Middleware     │
   ─────────────────────>│                                 │
                         │  1. Record start time            │
                         │  2. Call next middleware / app    │
                         │                                 │
                         │     ┌───────────────────────┐   │
                         │     │   Your Application     │   │
                         │     │                       │   │
                         │     │  Rails.logger.info()  │──>│── append to thread-local buffer
                         │     │  Rails.logger.warn()  │──>│── append to thread-local buffer
                         │     │                       │   │
                         │     └───────────────────────┘   │
                         │                                 │
                         │  3. Build log hash               │
                         │     - request data (path,        │
                         │       method, headers, params,   │
                         │       body)                      │
                         │     - response data (status,     │
                         │       headers, body)             │
                         │     - duration, thread/process   │
                         │     - exception (if any)         │
                         │  4. Drain custom log buffer      │
                         │  5. Apply transform hook          │
                         │  6. Filter sensitive params      │
                         │  7. Write single JSON line       │
                         │                                 │
    HTTP Response        │                                 │
   <─────────────────────│                                 │
                         └─────────────────────────────────┘
```

### Thread-Safe Log Accumulation

UnifiedLogger uses `Concurrent::ThreadLocalVar` from the [concurrent-ruby](https://github.com/ruby-concurrency/concurrent-ruby) gem to store in-app log calls. Each thread has its own isolated buffer, so concurrent requests in Puma or Sidekiq never cross-contaminate. The buffer is drained and reset after each request or job completes.

### Sensitive Data Filtering

All log output passes through `ActiveSupport::ParameterFilter` before being written. The filter uses pattern matching — a pattern like `:passw` will match `password`, `password_confirmation`, `current_password`, etc. Filtering is applied to request params, request bodies, response bodies, and the final log hash.

### Field Trimming

Large fields (request/response bodies, for example) are JSON-serialized and measured. If a field exceeds `max_log_field_size` (default: 2048 characters), it is truncated:

```
{"large_key":"very long value..."}... (4521 extra characters omitted)
```

This prevents a single large payload from blowing up your log storage.

### Exception & Backtrace Observation

UnifiedLogger acts as a pure observer for exceptions — it never rescues or re-raises. Both `RequestLogger` and `JobLogger` use an `ensure` block to run after the request or job completes (whether successfully or not), and check Ruby's `$ERROR_INFO` (`$!`) global to detect if an exception is in flight. If one is present, its details are read and added to the log entry:

- `class_name` — e.g., `"ActiveRecord::RecordNotFound"`
- `message` — the exception message
- `backtrace` — cleaned using `ActiveSupport::BacktraceCleaner`, which strips the project root prefix and silences internal middleware frames, leaving only your application code

The exception continues to propagate exactly as it would without UnifiedLogger — your existing error handling, rescue blocks, and exception reporting (Sentry, Bugsnag, etc.) are completely unaffected. UnifiedLogger simply records what happened on its way through.

This means every error in production is fully debuggable from a single log line: you get the request that caused it, the response status, the duration, any in-app logs leading up to the failure, and the complete cleaned backtrace — all in one place.

### Message Sanitization

All in-app log messages pass through `clean_log_message`, which:
1. Strips ANSI color codes (e.g., from Rails' colorized output)
2. Removes non-ASCII and non-printable characters
3. Normalizes double quotes to single quotes (for safe JSON embedding)
4. Collapses multiple whitespace into a single space

### Rails Integration

The `UnifiedLogger::Railtie` inserts the `RequestLogger` middleware after `ActionDispatch::DebugExceptions` in the Rails middleware stack, so exception data is available in `$ERROR_INFO` when the `ensure` block runs. It also supports Rails 7.1+ broadcast loggers — if `Rails.logger` is a broadcast, UnifiedLogger finds its own `Logger` instance within the broadcast chain.

---

## Compatibility

| | ActiveSupport 4.2 | 5.2 | 6.0 | 6.1 | 7.0 | 7.1 | 7.2 | 8.0 |
|---|---|---|---|---|---|---|---|---|
| **Ruby 2.4** | :white_check_mark: | | | | | | | |
| **Ruby 2.5** | | :white_check_mark: | | | | | | |
| **Ruby 2.7** | | | :white_check_mark: | :white_check_mark: | | | | |
| **Ruby 3.0** | | | | :white_check_mark: | :white_check_mark: | | | |
| **Ruby 3.1** | | | | | :white_check_mark: | :white_check_mark: | | |
| **Ruby 3.2** | | | | | | :white_check_mark: | :white_check_mark: | |
| **Ruby 3.3** | | | | | | | :white_check_mark: | :white_check_mark: |

Minimum requirements: **Ruby >= 2.4**, **ActiveSupport >= 4.2**, **Rack >= 1.6**.

---

## Development

```bash
bundle install
bundle exec rake test
```

### Testing Against Multiple ActiveSupport Versions

```bash
bundle exec appraisal install
bundle exec appraisal rake test
```

### Linting

```bash
bundle exec rubocop
```

---

## Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin my-feature`)
5. Open a Pull Request

Bug reports and pull requests are welcome on [GitHub](https://github.com/marcovecchio/unified_logger).

## License

The gem is available as open source under the terms of the [MIT License](LICENSE).
