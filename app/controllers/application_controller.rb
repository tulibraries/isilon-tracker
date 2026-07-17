class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has()
  allow_browser versions: :modern
  before_action :authenticate_user!, :ensure_active_user!

  include NavigationData
  include SessionTimeoutData

  private

  def ensure_active_user!
    return unless user_signed_in?
    return if current_user.active_status?

    sign_out current_user

    redirect_to(
      new_user_session_path,
      alert: "Your account is inactive."
    )
  end
end
