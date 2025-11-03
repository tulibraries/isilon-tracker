# frozen_string_literal: true

namespace :sync do
  desc "sync isilon assets"
  task :assets, [ :path ] => :environment do |_t, args|
    args.with_defaults(path: nil)
    SyncService::Assets.call(csv_path: args[:path])
  end

  desc "Process TIFF files for deduplication"
  task :tiffs, [ :volume_name ] => :environment do |_t, args|
    requested_volume = args[:volume_name].to_s

    if requested_volume.blank?
      puts "Error: volume_name argument is required"
      puts "Usage: rake sync:tiffs[deposit] or rake sync:tiffs[media-repository]"
      exit 1
    end

    valid_volumes = %w[Deposit Media-Repository]
    unless valid_volumes.map(&:downcase).include?(requested_volume.downcase)
      puts "Error: volume_name must be one of: #{valid_volumes.join(', ')}"
      exit 1
    end

    volume = Volume.where("LOWER(name) = ?", requested_volume.downcase).first
    unless volume
      puts "Error: Volume '#{requested_volume}' not found in database"
      exit 1
    end

    begin
      SyncService::Tiffs.call(volume_name: requested_volume)
    rescue => e
      puts "Error during TIFF processing: #{e.message}"
      puts e.backtrace.first(5).join("\n") if e.backtrace
      exit 1
    end
  end
end
