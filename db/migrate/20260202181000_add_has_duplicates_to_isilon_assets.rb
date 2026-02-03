class AddHasDuplicatesToIsilonAssets < ActiveRecord::Migration[7.1]
  def change
    add_column :isilon_assets, :has_duplicates, :boolean, null: false, default: false
    add_index :isilon_assets, :has_duplicates
  end
end
