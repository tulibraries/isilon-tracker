module ApplicationHelper
  def session_timeout_data
    data = { controller: "session-timeout" }
    return data unless user_signed_in?

    timeout_seconds = Rails.application.config.session_management.timeout.to_i
    warning_seconds = Rails.application.config.session_management.warning_lead_time.to_i

    session_data = warden_session_data
    last_request_at = session_data&.fetch("last_request_at", nil)

    expires_at =
      if last_request_at.present?
        last_request_at.to_i + timeout_seconds
      else
        Time.current.to_i + timeout_seconds
      end

    data.merge(
      session_timeout_expires_at_value: expires_at,
      session_timeout_duration_value: timeout_seconds,
      session_timeout_warning_offset_value: warning_seconds,
      session_timeout_keepalive_url_value: user_session_keepalive_path,
      session_timeout_warning_message_value: t("session_timeout.warning_message"),
      session_timeout_stay_signed_in_label_value: t("session_timeout.stay_signed_in"),
      session_timeout_error_message_value: t("session_timeout.error_message"),
      session_timeout_expired_message_value: t("session_timeout.expired_message")
    )
  end

  private

  def warden_session_data
    return {} unless defined?(warden) && warden.respond_to?(:session)

    warden.session(:user)
  rescue StandardError
    {}
  end
end
