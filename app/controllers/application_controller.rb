class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has()
  allow_browser versions: :modern

  include NavigationData

  before_action :authenticate_user!, unless: -> { Rails.env.development? }
  before_action :set_current_user_for_dev, if: -> { Rails.env.development? }

  private

  def set_current_user_for_dev
    # In development, create or use a default user for testing
    @current_user = User.first || User.create!(
      email: "dev@example.com",
      name: "Dev User",
      provider: "developer",
      uid: "dev-user-1"
    )
  end

  def current_user
    return @current_user if Rails.env.development? && @current_user
    super
  end
end
