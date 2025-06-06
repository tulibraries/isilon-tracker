class VolumeSerializer < ActiveModel::Serializer
  attributes :id, :name, :tree

  def tree
    object.isilon_folders.where(parent_folder_id: nil).map do |folder|
      IsilonFolderSerializer.new(folder).as_json
    end
  end
end


