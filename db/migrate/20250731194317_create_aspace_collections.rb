class CreateAspaceCollections < ActiveRecord::Migration[7.2]
  def change
    create_table :aspace_collections do |t|
      t.string :name
      t.boolean :active

      t.timestamps
    end
    add_index :aspace_collections, :name
  end
end
