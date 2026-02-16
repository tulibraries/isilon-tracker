class AddHasDescendantAssetsToIsilonFolders < ActiveRecord::Migration[7.2]
  def change
    add_column :isilon_folders, :has_descendant_assets, :boolean, null: false, default: false
  end
end
