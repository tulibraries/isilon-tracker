class IsilonAssetSerializer < ActiveModel::Serializer
  include Rails.application.routes.url_helpers

  attributes :title, :folder, :key, :isilon_date,
             :migration_status_id, :migration_status,
             :assigned_to_id, :assigned_to,
             :file_type, :file_size, :notes,
             :contentdm_collection_id, :aspace_collection_id,
             :preservica_reference_id, :aspace_linking_status,
             :is_duplicate,
             :url, :lazy, :parent_folder_id, :isilon_name, :path

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

  def is_duplicate
    object.has_duplicates
  end

  def lazy
    false
  end

  def migration_status_id
    object.migration_status&.id
  end

  def migration_status
    object.migration_status&.name.to_s
  end

  def assigned_to_id
    object.assigned_to&.id
  end

  def assigned_to
    object.assigned_to&.name.to_s.presence || "Unassigned"
  end


  def contentdm_collection_id
    object.contentdm_collection&.id
  end

  def aspace_collection_id
    object.aspace_collection&.id
  end

  def path
    pid = object.parent_folder_id
    return [] if pid.nil?

    pf = object.parent_folder
    return [] unless pf

    if pf.ancestors.respond_to?(:pluck)
      pf.ancestors.pluck(:id) + [ pf.id ]
    else
      Array(pf.ancestors).map { |n| n.is_a?(Integer) ? n : n.id } + [ pf.id ]
    end
  end
end
