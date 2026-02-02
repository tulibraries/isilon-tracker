# frozen_string_literal: true

class AddFullIsilonPathToIsilonAssets < ActiveRecord::Migration[7.2]
  def up
    add_column :isilon_assets, :full_isilon_path, :string
    add_index :isilon_assets, :full_isilon_path

    say_with_time "Backfilling full_isilon_path for existing assets" do
      IsilonAsset.reset_column_information

      IsilonAsset.includes(parent_folder: :volume).find_each(batch_size: 500) do |asset|
        volume_name = asset.parent_folder&.volume&.name
        next unless volume_name

        normalized_path = asset.isilon_path.to_s.sub(%r{\A/+}, "")
        asset.update_column(:full_isilon_path, "/#{volume_name}/#{normalized_path}")
      end
    end
  end

  def down
    remove_index :isilon_assets, :full_isilon_path
    remove_column :isilon_assets, :full_isilon_path
  end
end
