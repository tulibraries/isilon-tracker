class IsilonAssetSerializer < ActiveModel::Serializer
  attributes :title, :folder, :children, :key

  def title
    object.isilon_name
  end

  def folder
    false
  end

  def key
    "asset-#{object.id}"
  end

  def children
    []
  end
end

