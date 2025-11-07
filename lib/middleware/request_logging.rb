class RequestLogging
  def initialize(app)
    @app = app
  end

  def call(env)
    request_id = SecureRandom.uuid
    started_at = Time.current

    log_event("http_request_start",
      request_id: request_id,
      method: env["REQUEST_METHOD"],
      path: env["PATH_INFO"]
    )

    status, headers, response = @app.call(env)

    duration_ms = ((Time.current - started_at) * 1000).round(2)

    log_event("http_request_finish",
      request_id: request_id,
      status: status,
      duration_ms: duration_ms
    )

    [status, headers, response]
  rescue => e
    log_event("http_request_error",
      request_id: request_id,
      error: e.class.name,
      message: e.message
    )
    raise
  end

  private

  def log_event(event, **data)
    Rails.logger.info({
      ts: Time.current.iso8601,
      level: "info",
      svc: "license_management",
      env: Rails.env,
      event: event,
      **data
    }.to_json)
  end
end
