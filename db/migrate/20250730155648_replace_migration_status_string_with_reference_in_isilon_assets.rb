class ReplaceMigrationStatusStringWithReferenceInIsilonAssets < ActiveRecord::Migration[7.2]
  def change
     add_reference :isilon_assets, :migration_status, foreign_key: true
     remove_column :isilon_assets, :migration_status, :string
  end
end
