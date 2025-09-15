# frozen_string_literal: true

namespace :sync do
  desc "sync isilon assets"
  task :assets, [ :path ] => :environment do |_t, args|
    args.with_defaults(path: nil)
    SyncService::Assets.call(csv_path: args[:path])
  end

  desc "Process TIFF files for deduplication"
  task :tiffs, [ :volume_name ] => :environment do |_t, args|
    unless args[:volume_name]
      puts "Error: volume_name argument is required"
      puts "Usage: rake sync:tiffs[deposit] or rake sync:tiffs[media-repository]"
      exit 1
    end

    valid_volumes = %w[deposit media-repository]
    unless valid_volumes.include?(args[:volume_name])
      puts "Error: volume_name must be one of: #{valid_volumes.join(', ')}"
      exit 1
    end

    volume = Volume.find_by(name: args[:volume_name])
    unless volume
      puts "Error: Volume '#{args[:volume_name]}' not found in database"
      exit 1
    end

    begin
      SyncService::Tiffs.call(volume_name: args[:volume_name])
    rescue => e
      puts "Error during TIFF processing: #{e.message}"
      puts e.backtrace.first(5).join("\n") if e.backtrace
      exit 1
    end
  end
end
