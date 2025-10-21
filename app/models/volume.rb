class Volume < ApplicationRecord
  has_many :isilon_folders
  has_many :top_level_folders, -> { where(parent_folder_id: nil) }, class_name: "IsilonFolder"
  has_many :isilon_assets, through: :isilon_folders

  def asset_counts_by_migration_status
    isilon_assets
      .left_joins(:migration_status)
      .group(Arel.sql("COALESCE(#{MigrationStatus.table_name}.name, 'Unassigned')"))
      .order(Arel.sql("COALESCE(#{MigrationStatus.table_name}.name, 'Unassigned')"))
      .count
  end

  def asset_counts_by_assignee
    isilon_assets
      .left_joins(:assigned_to)
      .group(Arel.sql("COALESCE(#{User.table_name}.name, 'Unassigned')"))
      .order(Arel.sql("COALESCE(#{User.table_name}.name, 'Unassigned')"))
      .count
  end
end
