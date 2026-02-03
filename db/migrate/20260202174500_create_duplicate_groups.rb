class CreateDuplicateGroups < ActiveRecord::Migration[7.1]
  def change
    create_table :duplicate_groups do |t|
      t.string :checksum, null: false

      t.timestamps
    end

    add_index :duplicate_groups, :checksum, unique: true
  end
end
