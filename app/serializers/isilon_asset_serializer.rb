class IsilonAssetSerializer < ActiveModel::Serializer
  attributes :title, :folder, :children

  def title
    object.isilon_name
  end

  def folder
    false
  end

  def children
    []
  end
end

