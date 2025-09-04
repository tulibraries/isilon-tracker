class MigrationStatusesController < ApplicationController
  def index
    @migration_statuses = MigrationStatus.all
    render json: @migration_statuses.each_with_object({}) { |ms, h| h[ms.id] = ms.name }
  end
end
