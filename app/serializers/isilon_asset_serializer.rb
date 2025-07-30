class IsilonAssetSerializer < ActiveModel::Serializer
  attributes :title, :folder, :children, :key, :isilon_date, :migration_status,
  :assigned_to, :file_size, :notes, :contentdm_collection, :aspace_collection,
  :preservica_reference_id, :aspace_linking_status

  def title
    object.isilon_name
  end

  def folder
    false
  end

  def isilon_date
    object.date_created_in_isilon
  end

  def file_size
    ActiveSupport::NumberHelper.number_to_human_size(object.file_size)
  end

  def aspace_linking_status
    object.aspace_linking_status || false
  end

  def key
    "asset-#{object.id}"
  end

  def children
    []
  end

  def lazy
    true
  end
end
