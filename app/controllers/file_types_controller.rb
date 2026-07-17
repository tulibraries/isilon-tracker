# frozen_string_literal: true

class FileTypesController < ApplicationController
  def index
    scope = IsilonAsset.where.not(file_type: [ nil, "" ])
    scope = scope.where(volume_id: params[:volume_id]) if params[:volume_id].present?

    file_types = scope
      .where.not(file_type: [ nil, "" ])
      .distinct
      .pluck(:file_type)
      .filter_map { |value| FileTypeNormalizer.canonical(value) }
      .uniq
      .sort

    render json: file_types.index_with { |file_type| file_type }
  end
end
