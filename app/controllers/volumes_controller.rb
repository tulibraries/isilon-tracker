class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show file_tree_folders ]

  def file_tree
    volume = Volume.find(params[:id])
    root_folders = volume.isilon_folders.where(parent_folder_id: nil)
    render json: root_folders, each_serializer: IsilonFolderSerializer
  end

  def file_tree_folders
    volume = Volume.find(params[:id])
    ids    = Array(params[:parent_ids]).presence&.map!(&:to_i)
    pid    = params[:parent_folder_id].presence&.to_i

    scope = volume.isilon_folders
    scope = scope.where(parent_folder_id: ids) if ids.present?
    scope = scope.where(parent_folder_id: pid) if pid

    render json: scope, each_serializer: IsilonFolderSerializer
  end

  def file_tree_assets
    volume = Volume.find(params[:id])
    ids    = Array(params[:parent_ids]).presence&.map!(&:to_i)
    pid    = params[:parent_folder_id].presence&.to_i

    scope = volume.isilon_assets.includes(:parent_folder)
    scope = scope.where(parent_folder_id: ids) if ids.present?
    scope = scope.where(parent_folder_id: pid) if pid

    render json: scope, each_serializer: IsilonAssetSerializer
  end

  def file_tree_folders_search
    volume = Volume.find(params[:id])
    q = params[:q].to_s.strip
    return render(json: []) if q.blank?

    folders = volume.isilon_folders
                    .where("LOWER(full_path) LIKE ?", "%#{q.downcase}%")

    render json: folders, each_serializer: IsilonFolderSerializer
  end

  def file_tree_assets_search
    volume = Volume.find(params[:id])
    q = params[:q].to_s.strip
    return render(json: []) if q.blank?

    assets = volume.isilon_assets
                   .where("LOWER(isilon_name) LIKE ?", "%#{q.downcase}%")
                   .includes(:parent_folder)

    render json: assets, each_serializer: IsilonAssetSerializer
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
      params.fetch(:volume, {}).permit(:name, :id, :parent_folder_id)
    end
end
