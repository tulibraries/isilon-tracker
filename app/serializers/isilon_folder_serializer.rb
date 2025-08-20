class IsilonFolderSerializer < ActiveModel::Serializer
  attributes :title, :folder, :id, :lazy, :migration_status, :parent_folder_id, :path, :key

  def title
    object.full_path
  end

  def key
    object.id.to_s
  end

  def folder
    true
  end

  def lazy
    true
  end

  def migration_status
    object.migration_status&.id.to_s
  end

  def path
    return [] if object.respond_to?(:parent_folder_id) && object.parent_folder_id.nil?

    if object.ancestors.respond_to?(:pluck)
      object.ancestors.pluck(:id)
    else
      Array(object.ancestors).map { |node| node.is_a?(Integer) ? node : node.id }
    end
  end
end
