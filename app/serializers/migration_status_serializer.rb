class MigrationStatusSerializer < ActiveModel::Serializer
  include Rails.application.routes.url_helpers

  attributes :name, :id, :folder

  def folder
    false
  end
end
