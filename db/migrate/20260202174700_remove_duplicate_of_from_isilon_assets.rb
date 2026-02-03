class RemoveDuplicateOfFromIsilonAssets < ActiveRecord::Migration[7.1]
  def change
    remove_reference :isilon_assets,
      :duplicate_of,
      foreign_key: { to_table: :isilon_assets },
      index: true
  end
end
