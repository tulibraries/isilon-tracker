# frozen_string_literal: true

class AddIndexToIsilonAssetsOnVolumeIdAndFileType < ActiveRecord::Migration[8.1]
  def change
    add_index :isilon_assets, [ :volume_id, :file_type ]
  end
end
