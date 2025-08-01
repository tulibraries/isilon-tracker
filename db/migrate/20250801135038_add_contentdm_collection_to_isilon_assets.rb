class AddContentdmCollectionToIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    add_reference :isilon_assets, :contentdm_collection, null: true, foreign_key: true
  end
end
