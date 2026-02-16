class FileTreeSearchResultSerializer < ActiveModel::Serializer
  attributes :id, :folder, :parent_folder_id, :path,
             :migration_status, :assigned_to_id, :assigned_to,
             :has_descendant_assets

  def folder
    folder?
  end

  def parent_folder_id
    folder? ? object.parent_folder_id : object.parent_folder_id
  end

  def path
    if folder?
      ancestor_ids(object)
    else
      parent = object.parent_folder
      parent ? ancestor_ids(parent) + [ parent.id ] : []
    end
  end

  def migration_status
    return nil if folder?
    object.migration_status&.name.to_s
  end

  def assigned_to_id
    return nil if folder?
    object.assigned_to&.id
  end

  def assigned_to
    return nil if folder?
    object.assigned_to&.name.to_s
  end

  def has_descendant_assets
    return nil unless folder?
    object.has_descendant_assets
  end

  private

  def folder?
    object.is_a?(IsilonFolder)
  end

  def ancestor_ids(folder)
    ids = []
    current = folder
    while current&.parent_folder
      current = current.parent_folder
      ids.unshift(current.id)
    end
    ids
  end
end
