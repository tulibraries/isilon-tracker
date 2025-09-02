class UsersController < ApplicationController
  def index
    users = User.all
    render json: users.each_with_object({}) { |user, h| h[user.id] = user.name.presence || user.email }
  end
end
