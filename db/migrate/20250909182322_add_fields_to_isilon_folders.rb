class AddFieldsToIsilonFolders < ActiveRecord::Migration[7.2]
  def change
    # Only add columns if they don't already exist
    add_column :isilon_folders, :assigned_to, :integer unless column_exists?(:isilon_folders, :assigned_to)
    add_column :isilon_folders, :migration_status_id, :integer unless column_exists?(:isilon_folders, :migration_status_id)

    # Add indexes for performance, matching isilon_assets table
    add_index :isilon_folders, :assigned_to unless index_exists?(:isilon_folders, :assigned_to)
    add_index :isilon_folders, :migration_status_id unless index_exists?(:isilon_folders, :migration_status_id)

    # Add foreign key constraints, matching isilon_assets table
    add_foreign_key :isilon_folders, :users, column: :assigned_to unless foreign_key_exists?(:isilon_folders, :users, column: :assigned_to)
    add_foreign_key :isilon_folders, :migration_statuses unless foreign_key_exists?(:isilon_folders, :migration_statuses)
  end
end
