class AddFieldsToIsilonFolders < ActiveRecord::Migration[7.2]
  def change
    # Only add assigned_to column if it doesn't already exist
    add_column :isilon_folders, :assigned_to, :integer unless column_exists?(:isilon_folders, :assigned_to)

    # Add index for performance, matching isilon_assets table
    add_index :isilon_folders, :assigned_to unless index_exists?(:isilon_folders, :assigned_to)

    # Add foreign key constraint, matching isilon_assets table
    add_foreign_key :isilon_folders, :users, column: :assigned_to unless foreign_key_exists?(:isilon_folders, :users, column: :assigned_to)
  end
end
