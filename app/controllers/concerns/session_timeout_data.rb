module SessionTimeoutData
  extend ActiveSupport::Concern

  included do
    helper_method :session_timeout_data if respond_to?(:helper_method, true)
  end

  private

  def session_timeout_data
    data = { controller: "session-timeout" }
    return data unless user_signed_in?

    timeout_in_seconds = Devise.timeout_in.to_i
    session_data = request.env.fetch("warden", nil)&.session(:user) || {}
    last_request_at = session_data && session_data["last_request_at"]

    expires_at = if last_request_at.present?
                   last_request_at.to_i + timeout_in_seconds
                 else
                   Time.current.to_i + timeout_in_seconds
                 end

    data.merge(
      session_timeout_expires_at_value: expires_at,
      session_timeout_duration_value: timeout_in_seconds,
      session_timeout_warning_offset_value: Rails.application.config.session_management.warning_lead_time.to_i,
      session_timeout_keepalive_url_value: user_session_keepalive_path,
      session_timeout_warning_message_value: t("session_timeout.warning_message"),
      session_timeout_stay_signed_in_label_value: t("session_timeout.stay_signed_in"),
      session_timeout_error_message_value: t("session_timeout.error_message"),
      session_timeout_expired_message_value: t("session_timeout.expired_message")
    )
  end
end
