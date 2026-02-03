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

  desc "Export TIFF rule matches without updating migration_status"
  task :tiffs_export, [ :output_path, :volume_name ] => :environment do |_t, args|
    args.with_defaults(output_path: nil, volume_name: nil)
    SyncService::TiffsExport.call(
      output_path: args[:output_path],
      volume_name: args[:volume_name]
    )
  end
end
