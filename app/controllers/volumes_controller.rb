class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show ]
    def file_tree
      volume = Volume.find(params[:id])
      root_folders = volume.isilon_folders.where(parent_folder_id: nil)
      render json: root_folders, each_serializer: IsilonFolderSerializer
    end

    def file_tree_search
  query = params[:q].to_s.downcase
  volume = Volume.find(params[:id])

  folders = volume.isilon_folders
                 .where("LOWER(full_path) LIKE ?", "%#{query}%")
  assets  = volume.isilon_assets
                 .where("LOWER(isilon_name) LIKE ?", "%#{query}%")

  # Build ancestor folders for proper tree structure
  folder_ancestors = folders.flat_map(&:ancestors)
  asset_parents    = assets.map(&:parent_folder).compact
  asset_ancestors  = asset_parents.flat_map(&:ancestors)

  all_folders = (folders + folder_ancestors + asset_ancestors + asset_parents).uniq

  # ✅ Pre-serialize here
  folder_json = ActiveModelSerializers::SerializableResource.new(
    all_folders, each_serializer: IsilonFolderSerializer
  ).as_json

  asset_json = ActiveModelSerializers::SerializableResource.new(
    assets, each_serializer: IsilonAssetSerializer
  ).as_json

  # ✅ Combine plain hashes — don't re-serialize them
  render json: folder_json + asset_json

rescue => e
  logger.error "Search failed: #{e.message}\n#{e.backtrace.join("\n")}"
  render json: { error: e.message }, status: :internal_server_error
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
