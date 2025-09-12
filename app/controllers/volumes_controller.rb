class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show file_tree file_tree_folders file_tree_assets
    file_tree_folders_search file_tree_assets_search
    file_tree_updates ]

  def file_tree
    root_folders = @volume.isilon_folders.where(parent_folder_id: nil)
    render json: root_folders, each_serializer: IsilonFolderSerializer
  end

  def file_tree_folders
    ids    = Array(params[:parent_ids]).presence&.map!(&:to_i)
    pid    = params[:parent_folder_id].presence&.to_i

    scope = @volume.isilon_folders
    scope = scope.where(parent_folder_id: ids) if ids.present?
    scope = scope.where(parent_folder_id: pid) if pid

    render json: scope, each_serializer: IsilonFolderSerializer
  end

  def file_tree_assets
    ids    = Array(params[:parent_ids]).presence&.map!(&:to_i)
    pid    = params[:parent_folder_id].presence&.to_i

    scope = @volume.isilon_assets.includes(:parent_folder)
    scope = scope.where(parent_folder_id: ids) if ids.present?
    scope = scope.where(parent_folder_id: pid) if pid

    render json: scope, each_serializer: IsilonAssetSerializer
  end

  def file_tree_folders_search
    q = params[:q].to_s.strip
    return render(json: []) if q.blank?

    folders = @volume.isilon_folders
                    .where("LOWER(full_path) LIKE ?", "%#{q.downcase}%")

    render json: folders, each_serializer: IsilonFolderSerializer
  end

  def file_tree_assets_search
    q = params[:q].to_s.strip
    return render(json: []) if q.blank?

    assets = @volume.isilon_assets
                   .where("LOWER(isilon_name) LIKE ?", "%#{q.downcase}%")
                   .includes(:parent_folder)

    render json: assets, each_serializer: IsilonAssetSerializer
  end

  def file_tree_updates
    raw_id = params[:node_id].to_s
    record =
      if (id = raw_id.sub(/^a-/, "").to_i).positive?
        @volume.isilon_assets.find_by(id: id) or return render(
          json: { status: "error", errors: [ "Asset not found" ] },
          status: :not_found
        )
      else
        render json: { error: "Folder updates not supported" }, status: :unprocessable_entity
        return
      end

    field_map = {
      "migration_status" => "migration_status_id"
    }

    db_field = field_map[params[:field]] || params[:field]
    value = params[:value]
    value = value.to_i if db_field.end_with?("_id") && value.present?

    editable_fields = %w[
      migration_status_id
      contentdm_collection_id
      aspace_collection_id
      preservica_reference_id
      aspace_linking_status
      assigned_to
      notes
    ]

    unless editable_fields.include?(db_field)
      return render json: { status: "error", errors: [ "Invalid or non-editable field: #{db_field}" ] },
                    status: :unprocessable_entity
    end

    unless record.has_attribute?(db_field)
      return render json: { status: "error", errors: [ "Unknown field: #{db_field}" ] },
                    status: :unprocessable_entity
    end

    if record.update(db_field => value)
      label =
        case db_field
        when "contentdm_collection_id" then record.contentdm_collection&.name
        when "aspace_collection_id"    then record.aspace_collection&.name
        else record[db_field]
        end

      render json: { status: "ok", id: record.id, field: db_field, value: record.reload[db_field], label: label }
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
