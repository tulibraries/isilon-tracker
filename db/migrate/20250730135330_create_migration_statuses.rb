class CreateMigrationStatuses < ActiveRecord::Migration[7.2]
  def change
    create_table :migration_statuses do |t|
      t.string :name
      t.boolean :default
      t.boolean :active

      t.timestamps
    end
    add_index :migration_statuses, :name
  end
end
