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
    log_every = ENV.fetch("DUPLICATES_LOG_EVERY", "500").to_i
    slow_seconds = ENV.fetch("DUPLICATES_SLOW_SECONDS", "10").to_f
    large_group_size = ENV.fetch("DUPLICATES_LARGE_GROUP_SIZE", "20000").to_i

    puts "Scanning assets with matching checksums..."
    puts "Processing in batches of #{batch_size}..."

    main_volume_names = %w[Deposit Media-Repository]

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
    headers = [ "File", "Path", "Checksum", "File Size" ]
    CSV.open(output_path, "w", write_headers: true, headers: headers) do |csv|
      duplicate_checksums.each_slice(batch_size) do |checksum_batch|
        batch_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        checksum_batch.each_with_index do |checksum, index|
          started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

          main_scope = IsilonAsset.joins(parent_folder: :volume)
                                  .where(file_checksum: checksum, volumes: { name: main_volume_names })
          outside_scope = IsilonAsset.joins(parent_folder: :volume)
                                     .where(file_checksum: checksum)
                                     .where.not(volumes: { name: main_volume_names })

          next unless main_scope.exists?
          next unless outside_scope.exists?

          outside_scope.includes(parent_folder: :volume).find_each do |asset|
            full_path = build_full_path.call(asset)
            next unless full_path

            csv << [ asset.isilon_name, full_path, checksum, asset.file_size ]
            written += 1
          end

          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
          global_index = processed + index + 1
          if (global_index % log_every == 0) || elapsed >= slow_seconds || asset_ids.length >= large_group_size
            puts "Processed checksum #{global_index}/#{duplicate_checksums.length} (assets=#{asset_ids.length}) in #{format('%.2f', elapsed)}s"
          end
        end

        processed += checksum_batch.size
        GC.start

        if processed % progress_interval == 0
          puts "Processed #{processed} checksum groups..."
        end

        batch_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - batch_started_at
        puts "Batch complete (#{checksum_batch.size} checksums) in #{format('%.2f', batch_elapsed)}s"
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
