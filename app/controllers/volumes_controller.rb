class VolumesController < ApplicationController
  before_action :set_volume, only: %i[ show file_tree file_tree_folders file_tree_assets
    file_tree_folders_search file_tree_assets_search file_tree_filter_results
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
    assigned_to = params[:assigned_to].presence
    return render(json: []) if q.blank? && assigned_to.blank?

    folders = @volume.isilon_folders.includes(:parent_folder)

    folders = folders.where("LOWER(full_path) LIKE ?", "%#{q.downcase}%") if q.present?

    if assigned_to.present? && assigned_to != "unassigned"
      folders = folders.where(assigned_to_id: assigned_to)
    end

    folders = folders.where(assigned_to_id: nil) if assigned_to == "unassigned"

    render json: folders.map { |folder| FileTreeSearchResultSerializer.new(folder).as_json }
  end

  def file_tree_assets_search
    q = params[:q].to_s.strip.downcase

    scope = filtered_asset_scope(q)
    total_count = scope.count

    assets = scope.includes(parent_folder: :parent_folder)

    tree_nodes = assets.map do |asset|
      FileTreeSearchResultSerializer.new(asset).as_json
    end

    render json: {
      results: tree_nodes,
      total_count: total_count,
      returned_count: tree_nodes.size
    }
  end

  def file_tree_filter_results
    q = params[:q].to_s.strip
    assigned_to = params[:assigned_to].presence

    return render(json: empty_filter_results) if q.blank? && filter_params_blank?

    matched_folders = filtered_folder_scope(q, assigned_to).to_a
    matched_assets_scope = filtered_asset_scope(q.downcase)
    matched_assets = matched_assets_scope.includes(
      :assigned_to,
      :migration_status,
      :contentdm_collection,
      :aspace_collection,
      :parent_folder
    ).to_a

    visible_folder_ids = collect_visible_folder_ids(
      matched_folders.map(&:id) + matched_assets.map(&:parent_folder_id)
    )

    visible_folders = @volume.isilon_folders
      .where(id: visible_folder_ids)
      .includes(:assigned_to)
      .sort_by { |folder| [ folder.full_path.to_s.count("/"), folder.full_path.to_s ] }

    path_cache = build_visible_path_cache(visible_folders)
    folders_by_id = visible_folders.index_by(&:id)

    render json: {
      folders: serialize_filter_folders(visible_folders, path_cache),
      assets: serialize_filter_assets(matched_assets, folders_by_id, path_cache),
      matched_keys: matched_folders.map { |folder| folder.id.to_s } +
        matched_assets.map { |asset| "a-#{asset.id}" },
      matched_folder_count: matched_folders.size,
      matched_asset_count: matched_assets_scope.count,
      total_count: matched_folders.size + matched_assets_scope.count
    }
  end

  def file_tree_updates
    raw_id = params[:node_id].to_s
    node_type = params[:node_type].to_s

    record =
      if node_type == "asset"
        # Asset ID (should be prefixed with 'a-' but we'll handle both)
        id = raw_id.sub(/^a-/, "").to_i
        @volume.isilon_assets.find_by(id: id) or return render(
          json: { status: "error", errors: [ "Asset not found" ] },
          status: :not_found
        )
      elsif node_type == "folder"
        # Folder ID (plain number)
        id = raw_id.to_i
        @volume.isilon_folders.find_by(id: id) or return render(
          json: { status: "error", errors: [ "Folder not found" ] },
          status: :not_found
        )
      else
        render json: { error: "Invalid node type: #{node_type}" }, status: :unprocessable_entity
        return
      end

    field_map = {
      "migration_status" => "migration_status_id",
      "assigned_to" => "assigned_to_id"
    }

    db_field = field_map[params[:field]] || params[:field]
    value    = params[:value]

    if db_field == "assigned_to_id"
      if value.present? && value != "unassigned"
        user = User.find_by(id: value.to_i)
        unless user
          return render json: { status: "error", errors: [ "User not found" ] },
                        status: :unprocessable_entity
        end
        value = user.id
      else
        value = nil  # unassigned
      end
    elsif (db_field.end_with?("_id")) && value.present?
      # Convert to integer for other ID fields
      value = value.to_i
    end

    editable_fields = %w[
      migration_status_id
      contentdm_collection_id
      aspace_collection_id
      preservica_reference_id
      aspace_linking_status
      assigned_to_id
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
        when "assigned_to_id"          then record.assigned_to&.name
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
    def filtered_folder_scope(q, assigned_to = params[:assigned_to].presence)
      folders = @volume.isilon_folders.includes(:parent_folder)

      folders = folders.where("LOWER(full_path) LIKE ?", "%#{q.to_s.downcase}%") if q.present?

      if assigned_to.present? && assigned_to != "unassigned"
        folders = folders.where(assigned_to_id: assigned_to)
      end

      folders = folders.where(assigned_to_id: nil) if assigned_to == "unassigned"
      folders
    end

    def filtered_asset_scope(q = params[:q].to_s.strip.downcase)
      scope = @volume.isilon_assets.includes(:parent_folder)

      scope = scope.where("LOWER(isilon_name) LIKE ?", "%#{q}%") if q.present?
      scope = scope.where(migration_status: params[:migration_status]) if params[:migration_status].present?

      if params[:assigned_to].present? && params[:assigned_to] != "unassigned"
        scope = scope.where(assigned_to_id: params[:assigned_to])
      end

      if params[:file_type].present?
        normalized_file_type = params[:file_type].to_s.strip.downcase
        scope = scope.where("LOWER(TRIM(isilon_assets.file_type)) = ?", normalized_file_type)
      end

      scope = scope.where(contentdm_collection_id: params[:contentdm_collection_id]) if params[:contentdm_collection_id].present?
      scope = scope.where(aspace_collection_id: params[:aspace_collection_id]) if params[:aspace_collection_id].present?

      if params.key?(:aspace_linking_status)
        value = ActiveModel::Type::Boolean.new.cast(params[:aspace_linking_status])
        scope = scope.where(aspace_linking_status: value)
      end

      if params.key?(:is_duplicate)
        value = ActiveModel::Type::Boolean.new.cast(params[:is_duplicate])
        scope = scope.where(has_duplicates: value)
      end

      scope = scope.where(assigned_to_id: nil) if params[:assigned_to] == "unassigned"
      scope
    end

    def collect_visible_folder_ids(seed_ids)
      visible_ids = {}
      pending_ids = seed_ids.compact.map(&:to_i).uniq

      while pending_ids.any?
        batch = @volume.isilon_folders.where(id: pending_ids).pluck(:id, :parent_folder_id)
        pending_ids = []

        batch.each do |id, parent_id|
          next if visible_ids.key?(id)

          visible_ids[id] = true
          if parent_id.present? && !visible_ids.key?(parent_id)
            pending_ids << parent_id
          end
        end
      end

      visible_ids.keys
    end

    def build_visible_path_cache(folders)
      folders_by_id = folders.index_by(&:id)
      cache = {}

      build_path = lambda do |folder_id|
        return [] if folder_id.nil?
        return cache[folder_id] if cache.key?(folder_id)

        folder = folders_by_id[folder_id]
        return cache[folder_id] = [] unless folder

        parent_id = folder.parent_folder_id
        cache[folder_id] =
          if parent_id.nil?
            []
          else
            build_path.call(parent_id) + [ parent_id ]
          end
      end

      folders_by_id.each_key do |folder_id|
        build_path.call(folder_id)
      end

      cache
    end

    def serialize_filter_folders(folders, path_cache)
      folders.map do |folder|
        {
          title: folder_title(folder),
          full_path: folder.full_path,
          folder: true,
          id: folder.id,
          lazy: true,
          assigned_to_id: folder.assigned_to_id,
          assigned_to: folder.assigned_to&.name.to_s.presence || "Unassigned",
          descendant_assets_count: folder.descendant_assets_count,
          parent_folder_id: folder.parent_folder_id,
          path: path_cache[folder.id] || [],
          key: folder.id.to_s,
          notes: folder.notes
        }
      end
    end

    def serialize_filter_assets(assets, folders_by_id, path_cache)
      assets.map do |asset|
        parent_folder = folders_by_id[asset.parent_folder_id] || asset.parent_folder

        {
          title: asset.isilon_name,
          folder: false,
          key: "a-#{asset.id}",
          isilon_date: asset.date_created_in_isilon,
          migration_status_id: asset.migration_status&.id,
          migration_status: asset.migration_status&.name.to_s,
          assigned_to_id: asset.assigned_to_id,
          assigned_to: asset.assigned_to&.name.to_s.presence || "Unassigned",
          file_type: asset.file_type,
          file_size: ActiveSupport::NumberHelper.number_to_human_size(asset.file_size),
          notes: asset.notes,
          contentdm_collection_id: asset.contentdm_collection&.id,
          aspace_collection_id: asset.aspace_collection&.id,
          preservica_reference_id: asset.preservica_reference_id,
          aspace_linking_status: asset.aspace_linking_status || false,
          is_duplicate: asset.has_duplicates,
          url: helpers.admin_isilon_asset_path(asset.id),
          lazy: false,
          parent_folder_id: asset.parent_folder_id,
          isilon_name: asset.isilon_name,
          path: parent_folder ? (path_cache[parent_folder.id] || []) + [ parent_folder.id ] : []
        }
      end
    end

    def folder_title(folder)
      name = folder.full_path.to_s.split("/").reject(&:blank?).last
      name.presence || folder.full_path
    end

    def filter_params_blank?
      params[:migration_status].blank? &&
        params[:assigned_to].blank? &&
        params[:file_type].blank? &&
        params[:contentdm_collection_id].blank? &&
        params[:aspace_collection_id].blank? &&
        !params.key?(:aspace_linking_status) &&
        !params.key?(:is_duplicate)
    end

    def empty_filter_results
      {
        folders: [],
        assets: [],
        matched_keys: [],
        matched_folder_count: 0,
        matched_asset_count: 0,
        total_count: 0
      }
    end

    def set_volume
      @volume = Volume.find(params[:id])
    end

    def volume_params
      params.fetch(:volume, {}).permit(:name, :id, :parent_folder_id)
    end
end
