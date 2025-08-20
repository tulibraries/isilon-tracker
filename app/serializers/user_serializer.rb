class UserSerializer < ActiveModel::Serializer
  include Rails.application.routes.url_helpers

  attributes :name, :id, :folder

  def folder
    false
  end
end
