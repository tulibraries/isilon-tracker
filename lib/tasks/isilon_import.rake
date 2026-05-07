# frozen_string_literal: true

namespace :sync do
  desc "sync isilon assets"
  task :assets, [ :path ] => :environment do |_t, args|
    args.with_defaults(path: nil)
    SyncService::Assets.call(csv_path: args[:path])
  end

  desc "Update existing Isilon assets whose filenames match ContentDM CSV filenames"
  task :contentdm_filenames, [ :csv_folder ] => :environment do |_t, args|
    args.with_defaults(csv_folder: nil)

    result = SyncService::ContentdmFilenameSync.call(csv_folder: args[:csv_folder])

    puts "CSV rows: #{result.rows_touched}"
    puts "Asset(s) updated: #{result.updated_count}"
    puts "Unique Assets Updated: #{result.rows_matched}"
    puts "Ignored during dedupe/conflict resolution: #{result.rows_discarded}"
    puts "Unmatched rows (not in db): #{result.rows_unmatched}"
  end

  desc "Export TIFF rule matches without updating migration_status"
  task :tiffs_export, [ :output_path, :volume_name ] => :environment do |_t, args|
    args.with_defaults(output_path: nil, volume_name: nil)
    SyncService::TiffsExport.call(
      output_path: args[:output_path],
      volume_name: args[:volume_name]
    )
  end

  desc "Export assets that would trigger migration status rules"
  task :assets_rules_export, [ :output_path ] => :environment do |_t, args|
    args.with_defaults(output_path: nil)
    SyncService::AssetsRulesExport.call(output_path: args[:output_path])
  end

  desc "Remove assets that duplicate folder paths"
  task :cleanup_folder_assets, [ :volume_name ] => :environment do |_t, args|
    args.with_defaults(volume_name: nil)

    scope = IsilonAsset.joins("INNER JOIN isilon_folders ON isilon_folders.volume_id = isilon_assets.volume_id AND isilon_folders.full_path = isilon_assets.isilon_path")

    if args[:volume_name].present?
      volume = Volume.find_by("LOWER(name) = ?", args[:volume_name].to_s.downcase)
      if volume.nil?
        puts "Volume not found: #{args[:volume_name]}"
        next
      end

      scope = scope.where(volume_id: volume.id)
      puts "Cleaning assets for volume: #{volume.name} (#{volume.id})"
    else
      puts "Cleaning assets across all volumes"
    end

    count = scope.count
    puts "Found #{count} asset(s) with matching folder paths"
    scope.delete_all
    puts "Deleted #{count} asset(s)"
  end

  desc "Post-ingest housekeeping: cleanup folder-assets, backfill folder counts, detect duplicates"
  task :post_ingest, [ :volume_name ] => :environment do |_t, args|
    args.with_defaults(volume_name: nil)

    volume_name = args[:volume_name]

    puts "Running post-ingest housekeeping..."

    Rake::Task["sync:cleanup_folder_assets"].reenable
    Rake::Task["sync:cleanup_folder_assets"].invoke(volume_name)

    Rake::Task["folders:backfill_counts"].reenable
    Rake::Task["folders:backfill_counts"].invoke

    Rake::Task["duplicates:detect"].reenable
    Rake::Task["duplicates:detect"].invoke

    puts "Post-ingest housekeeping complete."
  end

  desc "Export TIFF rule matches without updating migration_status"
  task :tiffs_export, [ :output_path, :volume_name ] => :environment do |_t, args|
    args.with_defaults(output_path: nil, volume_name: nil)
    SyncService::TiffsExport.call(
      output_path: args[:output_path],
      volume_name: args[:volume_name]
    )
  end
end
