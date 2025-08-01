class RemoveContentdmCollectionStringFromIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    remove_column :isilon_assets, :contentdm_collection, :string
  end
end
