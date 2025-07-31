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

    def file_tree_children
      volume    = Volume.find(params[:id])
      parent_id = params.require(:parent_folder_id)

      folders = volume.isilon_folders.where(parent_folder_id: parent_id)
      assets  = volume.isilon_assets  .where(parent_folder_id: parent_id)

      folder_json = ActiveModelSerializers::SerializableResource
                    .new(folders, each_serializer: IsilonFolderSerializer)
                    .as_json
      asset_json  = ActiveModelSerializers::SerializableResource
                    .new(assets,  each_serializer: IsilonAssetSerializer)
                    .as_json

      render json: (folder_json + asset_json)
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
