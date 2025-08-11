class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show file_tree_folders ]
    def file_tree
      volume = Volume.find(params[:id])
      root_folders = volume.isilon_folders.where(parent_folder_id: nil)
      render json: root_folders, each_serializer: IsilonFolderSerializer
    end

    def file_tree_folders
  volume    = Volume.find(params[:id] || params[:volume_id])
  parent_id = params.require(:parent_folder_id)

  folders = volume.isilon_folders.where(parent_folder_id: parent_id)
  assets  = volume.isilon_assets.where(parent_folder_id: parent_id)

  folder_json = ActiveModelSerializers::SerializableResource.new(
    folders, each_serializer: IsilonFolderSerializer
  ).as_json

  asset_json = ActiveModelSerializers::SerializableResource.new(
    assets, each_serializer: IsilonAssetSerializer
  ).as_json

  render json: folder_json + asset_json
end

  def file_tree_search
  volume = Volume.find(params[:id] || params[:volume_id])
  q = params[:q].to_s.downcase

  folders = volume.isilon_folders.where("LOWER(full_path) LIKE ?", "%#{q}%")
  assets  = volume.isilon_assets.where("LOWER(isilon_name) LIKE ?", "%#{q}%")

  folder_json = ActiveModelSerializers::SerializableResource
                  .new(folders, each_serializer: IsilonFolderSerializer).as_json
  asset_json  = ActiveModelSerializers::SerializableResource
                  .new(assets, each_serializer: IsilonAssetSerializer).as_json

  payload = folder_json + asset_json
  render json: payload, adapter: nil  # ensure AMS doesn’t try to re-serialize hashes
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
