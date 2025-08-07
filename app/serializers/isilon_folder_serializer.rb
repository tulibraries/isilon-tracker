class IsilonFolderSerializer < ActiveModel::Serializer
  attributes :title, :folder, :id, :lazy, :migration_status

  def title
    object.full_path
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
end
