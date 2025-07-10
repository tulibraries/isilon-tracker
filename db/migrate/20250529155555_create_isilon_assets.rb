class CreateIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    create_table :isilon_assets do |t|
      t.timestamps
      t.string :file_size
      t.string :file_type
      t.string :isilon_path, null: false
      t.string :isilon_name, null: false
      t.string :last_modified_in_isilon
      t.string :date_created_in_isilon
      t.string :migration_status, default: "pending"
      t.string :contentdm_collection
      t.string :aspace_collection
      t.string :preservica_reference_id
      t.string :aspace_linking_status
      t.text :notes
      t.string :assigned_to, default: "unassigned"
      t.string :last_updated_by
      t.string :file_checksum
      # t.index :file_checksum, unique: true

      t.index :isilon_path, unique: true
    end
  end
end
