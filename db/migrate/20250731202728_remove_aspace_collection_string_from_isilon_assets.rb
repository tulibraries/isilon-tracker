class RemoveAspaceCollectionStringFromIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    remove_column :isilon_assets, :aspace_collection, :string
  end
end
