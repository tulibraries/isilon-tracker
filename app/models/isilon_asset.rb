class IsilonAsset < ApplicationRecord
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  belongs_to :migration_status, optional: true  # optional: true if some records are still NULL
  belongs_to :aspace_collection, optional: true
  belongs_to :contentdm_collection, optional: true
  belongs_to :assigned_to, class_name: "User", foreign_key: "assigned_to", optional: true

  has_many :duplicate_group_memberships, dependent: :delete_all
  has_many :duplicate_groups, through: :duplicate_group_memberships
  has_many :duplicates, -> { distinct }, through: :duplicate_groups, source: :isilon_assets

  before_validation :set_default_migration_status, on: :create

  def full_path_with_volume
    volume_name = parent_folder&.volume&.name
    return isilon_path unless volume_name.present?

    path = isilon_path.to_s
    path = "/#{path}" unless path.start_with?("/")
    "/#{volume_name}#{path}".gsub(%r{//+}, "/")
  end


  private

  def set_default_migration_status
    self.migration_status ||= MigrationStatus.find_by(default: true)
  end
end
