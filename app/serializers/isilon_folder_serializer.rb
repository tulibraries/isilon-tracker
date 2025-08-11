class IsilonFolderSerializer < ActiveModel::Serializer
  attributes :title, :folder, :id, :lazy, :parent_folder_id

  def title
    object.full_path
  end

  def folder
    true
  end

  def lazy
    true
  end
end
