# frozen_string_literal: true

class AddVolumeIdToIsilonAssets < ActiveRecord::Migration[7.2]
  def up
    add_reference :isilon_assets, :volume, foreign_key: true, index: false

    execute <<~SQL
      UPDATE isilon_assets
      SET volume_id = isilon_folders.volume_id
      FROM isilon_folders
      WHERE isilon_assets.parent_folder_id = isilon_folders.id
        AND isilon_assets.volume_id IS NULL
    SQL

    remove_index :isilon_assets, :isilon_path
    add_index :isilon_assets, [ :volume_id, :isilon_path ], unique: true
  end

  def down
    remove_index :isilon_assets, [ :volume_id, :isilon_path ]
    add_index :isilon_assets, :isilon_path, unique: true
    remove_reference :isilon_assets, :volume, foreign_key: true, index: false
  end
end
