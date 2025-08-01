class CreateContentdmCollections < ActiveRecord::Migration[7.2]
  def change
    create_table :contentdm_collections do |t|
      t.string :name
      t.boolean :active

      t.timestamps
    end
    add_index :contentdm_collections, :name
  end
end
