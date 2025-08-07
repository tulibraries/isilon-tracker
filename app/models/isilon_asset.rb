class IsilonAsset < ApplicationRecord
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  belongs_to :migration_status, optional: true  # optional: true if some records are still NULL
  belongs_to :aspace_collection, optional: true
  belongs_to :contentdm_collection, optional: true


  before_validation :set_default_migration_status, on: :create

  private

  def set_default_migration_status
    self.migration_status ||= MigrationStatus.find_by(default: true)
  end
end
