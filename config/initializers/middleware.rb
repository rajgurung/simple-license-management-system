require_relative '../../lib/middleware/request_logging'

Rails.application.config.middleware.use RequestLogging
