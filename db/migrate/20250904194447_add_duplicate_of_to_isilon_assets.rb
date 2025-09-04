class AddDuplicateOfToIsilonAssets < ActiveRecord::Migration[7.2]
  def change
    add_reference :isilon_assets, :duplicate_of, null: true, foreign_key: { to_table: :isilon_assets }, index: true
  end
end
