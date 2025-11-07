if ENV['SENTRY_DSN'].present?
  Sentry.init do |config|
    config.dsn = ENV['SENTRY_DSN']
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]

    # Set traces_sample_rate to capture performance data
    config.traces_sample_rate = 0.5

    # Set environment
    config.environment = Rails.env

    # Enable SQL query tracking
    config.send_default_pii = false
  end
end
