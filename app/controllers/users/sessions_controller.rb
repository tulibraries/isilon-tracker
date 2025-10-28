module Users
  # Handles session-related customizations for Devise
  class SessionsController < Devise::SessionsController
    before_action :authenticate_user!, only: :keepalive

    def keepalive
      expires_at = Time.current.to_i + Devise.timeout_in.to_i
      render json: { expires_at: expires_at }
    end
  end
end
