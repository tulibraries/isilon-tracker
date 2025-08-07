class IsilonFolderSerializer < ActiveModel::Serializer
  attributes :title, :folder, :id, :lazy, :path

  def title
    object.full_path
  end

  def folder
    true
  end

  def lazy
    true
  end

  def path
    return [] unless object.respond_to?(:parent_folder)

    ids = []
    current = object.parent_folder

    while current
      ids.unshift(current.id)
      current = current.parent_folder
    end

    ids
  end
end
