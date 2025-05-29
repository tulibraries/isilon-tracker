class CreateIsilonFolder < ActiveRecord::Migration[7.2]
  def change
    create_table :isilon_folders do |t|
      t.string :full_path
      t.index :full_path, unique: true

      t.timestamps
    end
  end
end
