module Users
  # Handles session-related customizations for Devise
  class SessionsController < Devise::SessionsController
    before_action :authenticate_user!, only: :keepalive
    skip_before_action :require_no_authentication, only: :new
    before_action :redirect_signed_in_users, only: :new

    def keepalive
      expires_at = Time.current.to_i + Devise.timeout_in.to_i
      render json: { expires_at: expires_at }
    end

    private

    def redirect_signed_in_users
      return unless user_signed_in?

      respond_to do |format|
        format.html { redirect_to after_sign_in_path_for(current_user) }
        format.any  { head :no_content }
      end
    end
  end
end
