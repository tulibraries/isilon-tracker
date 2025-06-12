class IsilonFolderSerializer < ActiveModel::Serializer
  attributes :title, :folder, :children, :key

  def title
    object.full_path
  end

  def key
    "folder-#{object.id}"
  end

  def folder
    true
  end

  def lazy
  true
  end

  def children
    # Serialize child folders recursively
    folder_children = object.child_folders.map do |child|
      IsilonFolderSerializer.new(child, scope: scope, root: false).as_json
    end

    # Add assets
    asset_children = object.isilon_assets.map do |asset|
      {
        title: asset.isilon_name,
        folder: false,
        children: []
      }
    end

    folder_children + asset_children
  end
end
