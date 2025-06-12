class VolumeSerializer < ActiveModel::Serializer
  attributes :id, :name, :tree

  def tree
    object.isilon_folders.where(parent_folder_id: nil).map do |folder|
      IsilonFolderSerializer.new(folder, scope: scope, root: false).serializable_hash
    end
  end
end
