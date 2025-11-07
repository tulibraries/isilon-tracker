class AddNotesToIsilonFolders < ActiveRecord::Migration[7.1]
  def change
    add_column :isilon_folders, :notes, :text
  end
end
