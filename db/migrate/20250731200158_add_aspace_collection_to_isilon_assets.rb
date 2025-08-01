class AddAspaceCollectionToIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    add_reference :isilon_assets, :aspace_collection, null: false, foreign_key: true, null: true
  end
end
