# lib/tasks/update_isilon_assets_migration_status.rake

namespace :isilon_assets do
  desc "Assign default migration_status to IsilonAssets without one"
  task assign_default_migration_status: :environment do
    default_status = MigrationStatus.find_by(default: true)

    if default_status.nil?
      puts "No default migration_status found. Please ensure one exists with default: true."
      next
    end

    assets_to_update = IsilonAsset.where(migration_status_id: nil)

    if assets_to_update.exists?
      puts "Updating #{assets_to_update.count} IsilonAssets..."
      assets_to_update.find_each(batch_size: 100) do |asset|
        asset.update!(migration_status: default_status)
      end
      puts "Update complete."
    else
      puts "No IsilonAssets without migration_status found."
    end
  end
end
