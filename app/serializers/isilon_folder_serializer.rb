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
    # 1) sub-folders
    folder_children = object.child_folders.map do |child|
      # This will recursively invoke IsilonFolderSerializer#children
      IsilonFolderSerializer
        .new(child, scope: scope, root: false)
        .as_json
        .merge(folder: true)
    end

    # 2) leaf assets
    asset_children = object.isilon_assets.map do |asset|
      IsilonAssetSerializer
        .new(asset, scope: scope, root: false)
        .as_json
        .merge(
          folder:   false,    # leaf node
          children: []        # no deeper nesting
        )
    end

    folder_children + asset_children
  end
end
