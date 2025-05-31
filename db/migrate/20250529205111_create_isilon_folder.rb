class CreateIsilonFolder < ActiveRecord::Migration[7.2]
  def change
    create_table :isilon_folders do |t|
      t.string :full_path, null: false
      t.index :full_path, unique: true
      t.references :volume, foreign_key: true
      t.references :parent_folder, foreign_key: { to_table: :isilon_folders }

      t.timestamps
    end
  end
end
