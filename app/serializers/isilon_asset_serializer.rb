class IsilonAssetSerializer < ActiveModel::Serializer
  include Rails.application.routes.url_helpers

  attributes :title, :folder, :isilon_date, :migration_status, :key,
  :assigned_to, :file_size, :notes, :contentdm_collection, :aspace_collection,
  :preservica_reference_id, :aspace_linking_status, :url, :lazy, :parent_folder_id, :isilon_name, :path

  def title
    object.isilon_name
  end

  def key
    "a-#{object.id}"
  end

  def url
    admin_isilon_asset_url(object.id)
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

  def lazy
    true
  end

  def path
    pid = object.parent_folder_id
    return [] if pid.nil?

    pf = object.parent_folder
    return [] unless pf

    if pf.ancestors.respond_to?(:pluck)
      pf.ancestors.pluck(:id) + [pf.id]
    else
      Array(pf.ancestors).map { |n| n.is_a?(Integer) ? n : n.id } + [pf.id]
    end
  end
end
