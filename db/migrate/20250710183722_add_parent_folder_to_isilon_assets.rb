class AddParentFolderToIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    add_reference :isilon_assets, :parent_folder, null: true, foreign_key: { to_table: :isilon_folders }
  end
end
