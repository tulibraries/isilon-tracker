class AddReportingIndexes < ActiveRecord::Migration[7.1]
  def up
    add_index :isilon_assets, [ :parent_folder_id, :migration_status_id ],
      name: "index_isilon_assets_on_parent_folder_and_migration_status"

    add_index :isilon_assets, [ :assigned_to, :migration_status_id ],
      name: "index_isilon_assets_on_assigned_to_and_migration_status"

    execute <<~SQL
      CREATE INDEX index_migration_statuses_on_lower_name
      ON migration_statuses ((LOWER(name)));
    SQL
  end

  def down
    remove_index :isilon_assets,
      name: "index_isilon_assets_on_parent_folder_and_migration_status"

    remove_index :isilon_assets,
      name: "index_isilon_assets_on_assigned_to_and_migration_status"

    execute <<~SQL
      DROP INDEX IF EXISTS index_migration_statuses_on_lower_name;
    SQL
  end
end
