class CleanupIsilonFoldersColumns < ActiveRecord::Migration[7.2]
  def change
    # Remove foreign key constraints first
    if foreign_key_exists?(:isilon_folders, :migration_statuses)
      remove_foreign_key :isilon_folders, :migration_statuses
    end

    if foreign_key_exists?(:isilon_folders, :users, column: :assigned_to_id)
      remove_foreign_key :isilon_folders, :users, column: :assigned_to_id
    end

    # Remove indexes
    if index_exists?(:isilon_folders, :migration_status_id)
      remove_index :isilon_folders, :migration_status_id
    end

    if index_exists?(:isilon_folders, :assigned_to_id)
      remove_index :isilon_folders, :assigned_to_id
    end

    # Remove the unwanted columns
    if column_exists?(:isilon_folders, :migration_status_id)
      remove_column :isilon_folders, :migration_status_id, :integer
    end

    if column_exists?(:isilon_folders, :assigned_to_id)
      remove_column :isilon_folders, :assigned_to_id, :integer
    end
  end
end
