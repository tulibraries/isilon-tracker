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

  desc "Backfill has_descendant_assets for folders"
  task :refresh_folder_descendant_assets, [ :volume_name ] => :environment do |_t, args|
    args.with_defaults(volume_name: nil)

    folders = IsilonFolder.all
    assets = IsilonAsset.where.not(parent_folder_id: nil)
    volume = nil

    if args[:volume_name].present?
      volume = Volume.find_by("LOWER(name) = ?", args[:volume_name].to_s.downcase)
      if volume.nil?
        puts "Volume not found: #{args[:volume_name]}"
        next
      end

      folders = folders.where(volume_id: volume.id)
      assets = assets.where(volume_id: volume.id)
      puts "Refreshing folder descendant flags for volume: #{volume.name} (#{volume.id})"
    else
      puts "Refreshing folder descendant flags across all volumes"
    end

    folders.update_all(has_descendant_assets: false)

    if assets.none?
      puts "No assets found; all folders marked empty."
      next
    end

    volume_filter = volume ? " AND volume_id = #{volume.id}" : ""
    folder_volume_filter = volume ? " AND f.volume_id = #{volume.id}" : ""
    update_volume_filter = volume ? " AND volume_id = #{volume.id}" : ""

    sql = <<~SQL.squish
      WITH RECURSIVE ancestors AS (
        SELECT parent_folder_id AS folder_id
        FROM isilon_assets
        WHERE parent_folder_id IS NOT NULL#{volume_filter}
        UNION
        SELECT f.parent_folder_id
        FROM isilon_folders f
        INNER JOIN ancestors a ON f.id = a.folder_id
        WHERE f.parent_folder_id IS NOT NULL#{folder_volume_filter}
      )
      UPDATE isilon_folders
      SET has_descendant_assets = TRUE
      WHERE id IN (SELECT DISTINCT folder_id FROM ancestors)#{update_volume_filter}
    SQL

    ActiveRecord::Base.connection.execute(sql)
    puts "Updated folder descendant flags."
  end

  desc "Post-ingest housekeeping: cleanup folder-assets, refresh empty-folder flags, detect duplicates"
  task :post_ingest, [ :volume_name ] => :environment do |_t, args|
    args.with_defaults(volume_name: nil)

    volume_name = args[:volume_name]

    puts "Running post-ingest housekeeping..."

    Rake::Task["sync:cleanup_folder_assets"].reenable
    Rake::Task["sync:cleanup_folder_assets"].invoke(volume_name)

    Rake::Task["sync:refresh_folder_descendant_assets"].reenable
    Rake::Task["sync:refresh_folder_descendant_assets"].invoke(volume_name)

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
