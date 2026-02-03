class CreateDuplicateGroupMemberships < ActiveRecord::Migration[7.1]
  def change
    create_table :duplicate_group_memberships do |t|
      t.references :duplicate_group, null: false, foreign_key: true
      t.references :isilon_asset, null: false, foreign_key: true

      t.timestamps
    end

    add_index :duplicate_group_memberships,
      [ :duplicate_group_id, :isilon_asset_id ],
      unique: true,
      name: "index_duplicate_group_memberships_unique"
  end
end
