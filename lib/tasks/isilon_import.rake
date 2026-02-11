# frozen_string_literal: true

namespace :sync do
  desc "sync isilon assets"
  task :assets, [ :path ] => :environment do |_t, args|
    args.with_defaults(path: nil)
    SyncService::Assets.call(csv_path: args[:path])
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

  desc "Export TIFF rule matches without updating migration_status"
  task :tiffs_export, [ :output_path, :volume_name ] => :environment do |_t, args|
    args.with_defaults(output_path: nil, volume_name: nil)
    SyncService::TiffsExport.call(
      output_path: args[:output_path],
      volume_name: args[:volume_name]
    )
  end
end
