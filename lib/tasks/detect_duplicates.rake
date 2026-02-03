# frozen_string_literal: true

require "csv"

namespace :duplicates do
  desc "Detect and list duplicates according to Rule 3"
  task detect: :environment do
    puts "Starting Rule 3 duplicate detection..."

    # Find all assets outside main areas with non-empty checksums
    output_path = "log/isilon-duplicate-paths.csv"
    processed = 0
    batch_size = 1000
    progress_interval = batch_size * 5

    puts "Scanning assets with matching checksums..."
    puts "Processing in batches of #{batch_size}..."

    duplicate_checksums = IsilonAsset.where("NULLIF(TRIM(file_checksum), '') IS NOT NULL")
                                     .group(:file_checksum)
                                     .having("COUNT(*) > 1")
                                     .pluck(:file_checksum)

    build_full_path = lambda do |asset|
      parent = asset.parent_folder
      return nil unless parent

      volume = parent.volume
      return nil unless volume

      path = asset.isilon_path.to_s
      path = "/#{path}" unless path.start_with?("/")
      "/#{volume.name}#{path}".gsub(%r{//+}, "/")
    end

    written = 0
    CSV.open(output_path, "w", write_headers: true, headers: [ "FullPath" ]) do |csv|
      duplicate_checksums.each_slice(batch_size) do |checksum_batch|
        checksum_batch.each do |checksum|
          asset_ids = IsilonAsset.where(file_checksum: checksum).pluck(:id)
          next if asset_ids.empty?

          group = DuplicateGroup.find_or_create_by!(checksum: checksum)
          group.duplicate_group_memberships.delete_all

          now = Time.current
          rows = asset_ids.map do |asset_id|
            {
              duplicate_group_id: group.id,
              isilon_asset_id: asset_id,
              created_at: now,
              updated_at: now
            }
          end
          DuplicateGroupMembership.insert_all(rows) if rows.any?
          IsilonAsset.where(id: asset_ids).update_all(has_duplicates: true)

          IsilonAsset.where(id: asset_ids)
                     .includes(parent_folder: :volume)
                     .find_each do |asset|
            full_path = build_full_path.call(asset)
            next unless full_path

            csv << [ full_path ]
            written += 1
          end
        end

        processed += checksum_batch.size
        GC.start

        if processed % progress_interval == 0
          puts "Processed #{processed} checksum groups..."
        end
      end
    end

    puts "\n✓ Complete!"
    puts "Processed: #{processed} checksum groups"
    puts "Duplicate paths exported to #{output_path} (#{written} rows)"
  end

  desc "Show duplicate statistics"
  task stats: :environment do
    duplicate_groups = DuplicateGroup.count
    total_duplicates = DuplicateGroupMembership.count

    puts "Duplicate Statistics:"
    puts "===================="
    puts "Duplicate checksum groups: #{duplicate_groups}"
    puts "Assets in duplicate groups: #{total_duplicates}"
  end

  desc "Clear all duplicate groups and reset has_duplicates"
  task clear: :environment do
    group_count = DuplicateGroup.count
    membership_count = DuplicateGroupMembership.count

    if group_count.positive?
      print "Are you sure you want to clear #{group_count} duplicate groups? (yes/no): "
      response = STDIN.gets.chomp

      if response.downcase == "yes"
        DuplicateGroupMembership.delete_all
        DuplicateGroup.delete_all
        IsilonAsset.update_all(has_duplicates: false)
        puts "✓ Cleared #{group_count} duplicate groups and reset has_duplicates"
      else
        puts "Cancelled"
      end
    else
      puts "No duplicate groups to clear"
    end
  end
end
