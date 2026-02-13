class RenameIsilonFoldersAssignedToId < ActiveRecord::Migration[7.2]
  def up
    if foreign_key_exists?(:isilon_folders, :users, column: :assigned_to)
      remove_foreign_key :isilon_folders, :users, column: :assigned_to
    end

    if index_exists?(:isilon_folders, :assigned_to, name: "index_isilon_folders_on_assigned_to")
      remove_index :isilon_folders, name: "index_isilon_folders_on_assigned_to"
    end

    rename_column :isilon_folders, :assigned_to, :assigned_to_id

    add_index :isilon_folders, :assigned_to_id
    add_foreign_key :isilon_folders, :users, column: :assigned_to_id
  end

  def down
    if foreign_key_exists?(:isilon_folders, :users, column: :assigned_to_id)
      remove_foreign_key :isilon_folders, :users, column: :assigned_to_id
    end

    if index_exists?(:isilon_folders, :assigned_to_id, name: "index_isilon_folders_on_assigned_to_id")
      remove_index :isilon_folders, name: "index_isilon_folders_on_assigned_to_id"
    end

    rename_column :isilon_folders, :assigned_to_id, :assigned_to

    add_index :isilon_folders, :assigned_to
    add_foreign_key :isilon_folders, :users, column: :assigned_to
  end
end
