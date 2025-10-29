class ChangeIsilonFoldersUniqueIndex < ActiveRecord::Migration[7.1]
  def change
    remove_index :isilon_folders, :full_path
    add_index :isilon_folders, %i[volume_id full_path], unique: true, name: "index_isilon_folders_on_volume_id_and_full_path"
  end
end
