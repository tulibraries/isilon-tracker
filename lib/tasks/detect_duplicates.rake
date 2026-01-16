# frozen_string_literal: true

namespace :duplicates do
  desc "Detect and mark duplicates according to Rule 3"
  task detect: :environment do
    puts "Starting Rule 3 duplicate detection..."

    dont_migrate_status = MigrationStatus.find_by(name: "Don't migrate")

    unless dont_migrate_status
      puts "ERROR: 'Don't migrate' status not found. Please create it first."
      exit 1
    end

    main_volume_names = %w[Deposit Media-Repository]

    # Find all assets outside main areas with non-empty checksums
    outside_main = IsilonAsset.joins(parent_folder: :volume)
                              .where.not(file_checksum: nil)
                              .where.not(file_size: [ "0", "0.0", nil, "" ])
                              .where.not(volumes: { name: main_volume_names })

    processed = 0
    duplicates_found = 0
    batch_size = 1000
    progress_interval = batch_size * 5

    puts "Scanning assets outside main areas..."
    puts "Processing in batches of #{batch_size}..."

    outside_main.find_in_batches(batch_size: batch_size) do |batch|
      checksums = batch.map(&:file_checksum).compact.uniq
      originals_by_checksum = if checksums.empty?
        {}
      else
        # Map checksum => oldest original id in main areas.
        IsilonAsset.joins(parent_folder: :volume)
                   .where(file_checksum: checksums)
                   .where(volumes: { name: main_volume_names })
                   .group(:file_checksum)
                   .minimum(:id)
      end

      updates_by_original = Hash.new { |hash, key| hash[key] = [] }
      batch.each do |asset|
        original_id = originals_by_checksum[asset.file_checksum]
        next unless original_id
        next if original_id == asset.id

        updates_by_original[original_id] << asset.id
      end

      updates_by_original.each do |original_id, asset_ids|
        IsilonAsset.where(id: asset_ids).update_all(
          duplicate_of_id: original_id,
          migration_status_id: dont_migrate_status.id
        )
        duplicates_found += asset_ids.length
      end

      processed += batch.size

      # Trigger garbage collection periodically
      GC.start

      # Progress indicator
      if processed % progress_interval == 0
        puts "Processed #{processed} assets (#{duplicates_found} duplicates found)..."
      end
    end

    puts "\n✓ Complete!"
    puts "Processed: #{processed} assets"
    puts "Duplicates found and marked: #{duplicates_found}"
    puts "Migration status updated to 'Don't migrate': #{duplicates_found}"
  end

  desc "Show duplicate statistics"
  task stats: :environment do
    total_duplicates = IsilonAsset.where.not(duplicate_of_id: nil).count

    puts "Duplicate Statistics:"
    puts "===================="
    puts "Assets marked as duplicates: #{total_duplicates}"

    if total_duplicates > 0
      # Show some examples
      puts "\nExample duplicates:"
      IsilonAsset.where.not(duplicate_of_id: nil)
                 .includes(:duplicate_of)
                 .limit(5)
                 .each do |dup|
        puts "  Duplicate: #{dup.isilon_path}"
        puts "  Original:  #{dup.duplicate_of&.isilon_path}"
        puts "  Checksum:  #{dup.file_checksum}"
        puts ""
      end
    end
  end

  desc "Clear all duplicate_of_id assignments"
  task clear: :environment do
    count = IsilonAsset.where.not(duplicate_of_id: nil).count

    if count > 0
      print "Are you sure you want to clear #{count} duplicate assignments? (yes/no): "
      response = STDIN.gets.chomp

      if response.downcase == "yes"
        IsilonAsset.where.not(duplicate_of_id: nil).update_all(duplicate_of_id: nil)
        puts "✓ Cleared #{count} duplicate assignments"
      else
        puts "Cancelled"
      end
    else
      puts "No duplicate assignments to clear"
    end
  end
end
