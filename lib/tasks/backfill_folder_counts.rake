namespace :folders do
  desc "Backfill descendant_assets_count"
  task backfill_counts: :environment do
    IsilonFolder.find_each do |folder|
      ids = [ folder.id ] + folder.descendant_folders.map(&:id)
      count = IsilonAsset.where(parent_folder_id: ids).count
      folder.update_column(:descendant_assets_count, count)
    end
  end
end
