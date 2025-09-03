class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show file_tree file_tree_folders file_tree_assets
    file_tree_folders_search file_tree_assets_search
    file_tree_updates ]

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

  def file_tree_updates
    raw_id = params[:node_id].to_s
    record =
      if params[:node_type] == "folder"
        @volume.isilon_folders.find(raw_id.sub(/^f-/, "").to_i)
      else
        id = raw_id.sub(/^a-/, "").to_i
        @volume.isilon_assets.find(id)
      end

    field_map = {
      "migration_status"      => "migration_status_id",
      "contentdm_collection"  => "contentdm_collection_id",
      "aspace_collection"     => "aspace_collection_id"
    }

    db_field = field_map[params[:field]] || params[:field]
    value = params[:value]
    value = value.to_i if db_field.ends_with?("_id") && value.present?

    if record.respond_to?(db_field) && record.update(db_field => value)
      render json: { status: "ok", id: record.id, field: db_field, value: value }
    else
      render json: { status: "error", errors: record.errors.full_messages },
            status: :unprocessable_entity
    end
  end

  def index
    @volumes = Volume.all
  end

  private
    def set_volume
      @volume = Volume.find(params[:id])
    end

    def volume_params
      params.fetch(:volume, {}).permit(:name, :id, :parent_folder_id)
    end
end
