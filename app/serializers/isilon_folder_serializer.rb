class IsilonFolderSerializer < ActiveModel::Serializer
  attributes :title, :folder, :id, :lazy,
             :assigned_to_id, :assigned_to,
             :parent_folder_id, :path, :key, :notes

  def title
    name = object.full_path.to_s.split("/").reject(&:blank?).last
    name.presence || object.full_path
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

  def assigned_to_id
    object.assigned_to&.id
  end

  def assigned_to
    object.assigned_to&.name.to_s.presence || "Unassigned"
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
