class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has()
  allow_browser versions: :modern
  before_action :authenticate_user!

  include NavigationData


  private

  def current_user
    return @current_user if Rails.env.development? && @current_user
    super
  end
end
