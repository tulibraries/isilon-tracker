class IsilonAsset < ApplicationRecord
  belongs_to :parent_folder, class_name: "IsilonFolder", foreign_key: "parent_folder_id", optional: true
  belongs_to :migration_status, optional: true  # optional: true if some records are still NULL
  belongs_to :aspace_collection, optional: true
  belongs_to :contentdm_collection, optional: true
  belongs_to :assigned_to, class_name: "User", foreign_key: "assigned_to", optional: true

  # Self-referencing association for duplicate tracking
  belongs_to :duplicate_of, class_name: "IsilonAsset", foreign_key: "duplicate_of_id", optional: true
  has_many :linked_duplicates,
    class_name: "IsilonAsset",
    foreign_key: "duplicate_of_id",
    inverse_of: :duplicate_of,
    dependent: :nullify

  before_validation :set_default_migration_status, on: :create

  # Returns other assets that share the same checksum as this record, ordered by name.
  def duplicates
    return IsilonAsset.none if file_checksum.blank?

    IsilonAsset
      .where(file_checksum:)
      .where.not(id:)
      .order(:isilon_name)
  end

  private

  def set_default_migration_status
    self.migration_status ||= MigrationStatus.find_by(default: true)
  end
end
