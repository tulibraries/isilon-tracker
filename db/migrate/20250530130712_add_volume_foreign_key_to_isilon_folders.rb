class AddVolumeForeignKeyToIsilonFolders < ActiveRecord::Migration[7.2]
  def change
    add_foreign_key :isilon_folders, :volumes
  end
end
