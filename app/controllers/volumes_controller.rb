class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show ]
    def file_tree
      volume = Volume.find(params[:id])
      root_folders = volume.isilon_folders.where(parent_folder_id: nil)
      render json: root_folders, each_serializer: IsilonFolderSerializer
    end

    def index
      @volumes = Volume.all
    end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_volume
      @volume = Volume.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def volume_params
      params.fetch(:volume, {})
    end
end
