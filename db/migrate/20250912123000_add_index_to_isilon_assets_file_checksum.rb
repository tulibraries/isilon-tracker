class AddIndexToIsilonAssetsFileChecksum < ActiveRecord::Migration[7.1]
  def change
    add_index :isilon_assets, :file_checksum
  end
end
