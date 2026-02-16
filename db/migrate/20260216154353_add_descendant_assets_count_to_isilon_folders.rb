class AddDescendantAssetsCountToIsilonFolders < ActiveRecord::Migration[7.2]
  def change
    add_column :isilon_folders, :descendant_assets_count, :integer, default: 0, null: false
    add_index :isilon_folders, :descendant_assets_count
  end
end
