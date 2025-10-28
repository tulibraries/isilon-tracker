module Users
  # Handles session-related customizations for Devise
  class SessionsController < Devise::SessionsController
    before_action :authenticate_user!, only: :keepalive

    def keepalive
      # Simply touching the session by responding updates Devise's last_request_at timestamp
      head :no_content
    end
  end
end
