class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show ]
  before_action :authenticate_user, only: %i[ show ]

    def file_tree
      volume = Volume.find(params[:id])
      root_folders = volume.isilon_folders.where(parent_folder_id: nil)
      render json: root_folders, each_serializer: IsilonFolderSerializer
    end

    def file_tree_children
      volume = Volume.find(params[:id])
      parent_id = params.require(:parent_folder_id)

      folders = volume.isilon_folders.where(parent_folder_id: parent_id)
      assets  = volume.isilon_assets.where(parent_folder_id: parent_id)

      resources = folders.to_a + assets.to_a
      render json: resources
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
      params.fetch(:volume, {}).permit(:name, :id)
    end
end
