class RenameIsilonAssetsAssignedToId < ActiveRecord::Migration[7.2]
  def up
    if index_name_exists?(:isilon_assets, "index_isilon_assets_on_assigned_to")
      remove_index :isilon_assets, name: "index_isilon_assets_on_assigned_to"
    end
    if index_name_exists?(:isilon_assets, "index_isilon_assets_on_assigned_to_and_migration_status")
      remove_index :isilon_assets, name: "index_isilon_assets_on_assigned_to_and_migration_status"
    end

    rename_column :isilon_assets, :assigned_to, :assigned_to_id

    add_index :isilon_assets, :assigned_to_id
    add_index :isilon_assets, [ :assigned_to_id, :migration_status_id ],
      name: "index_isilon_assets_on_assigned_to_id_and_migration_status"
  end

  def down
    if index_name_exists?(:isilon_assets, "index_isilon_assets_on_assigned_to_id")
      remove_index :isilon_assets, name: "index_isilon_assets_on_assigned_to_id"
    end
    if index_name_exists?(:isilon_assets, "index_isilon_assets_on_assigned_to_id_and_migration_status")
      remove_index :isilon_assets, name: "index_isilon_assets_on_assigned_to_id_and_migration_status"
    end

    rename_column :isilon_assets, :assigned_to_id, :assigned_to

    add_index :isilon_assets, :assigned_to
    add_index :isilon_assets, [ :assigned_to, :migration_status_id ],
      name: "index_isilon_assets_on_assigned_to_and_migration_status"
  end
end
