# frozen_string_literal: true

class FileTypesController < ApplicationController
  def index
    scope = IsilonAsset.where.not(file_type: [ nil, "" ])
    scope = scope.where(volume_id: params[:volume_id]) if params[:volume_id].present?

    file_types = scope
                           .distinct
                           .order(:file_type)
                           .pluck(:file_type)

    render json: file_types.index_with { |file_type| file_type }
  end
end
