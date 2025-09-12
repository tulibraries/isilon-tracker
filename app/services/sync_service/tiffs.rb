# frozen_string_literal: true

require "logger"
require "ostruct"

module SyncService
  class Tiffs
    def self.call(volume_name: nil)
      new(volume_name: volume_name).process
    end

    def initialize(volume_name: nil)
      @volume_name = volume_name
      @log = Logger.new("log/isilon-post-processing.log")
      @stdout = Logger.new($stdout)

      if @volume_name
        @parent_volume = Volume.find_by(name: @volume_name)
        raise ArgumentError, "Volume '#{@volume_name}' not found" unless @parent_volume
        stdout_and_log("Starting post-processing for volume: #{@volume_name}")
      else
        @parent_volume = nil  # Will process all volumes
        stdout_and_log("Starting post-processing for all volumes")
      end
    end

    def process
      stdout_and_log("Starting Rule 4 post-processing for TIFF comparison...")

      begin
        # Use ActiveRecord to find parent directories with matching TIFF counts
        parent_dirs_with_counts = find_parent_dirs_with_matching_tiff_counts_ar

        stdout_and_log("Found #{parent_dirs_with_counts.size} parent directories with matching TIFF counts")

        # Update unprocessed TIFFs in bulk
        total_updated = 0
        parent_dirs_with_counts.each do |parent_info|
          updated = mark_unprocessed_tiffs_as_dont_migrate(parent_info[:parent_dir], parent_info[:processed_count])
          total_updated += updated
        end

        stdout_and_log("Rule 4 post-processing completed. Updated #{total_updated} assets.")

        OpenStruct.new(
          success?: true,
          tiff_comparisons_updated: parent_dirs_with_counts.size,
          migration_statuses_updated: total_updated,
          error_message: nil
        )
      rescue => e
        error_msg = "Post-processing failed: #{e.message}"
        stdout_and_log(error_msg, level: :error)

        OpenStruct.new(
          success?: false,
          tiff_comparisons_updated: 0,
          migration_statuses_updated: 0,
          error_message: error_msg
        )
      end
    end

    private

    def find_parent_dirs_with_matching_tiff_counts_ar
      # Base query for all TIFF assets in deposit folders (excluding scrc accessions)
      base_query = build_base_tiff_query

      # Get all matching assets and group them in Ruby
      assets = base_query.pluck(:isilon_path)

      # Group assets by parent directory and classify as processed/unprocessed
      parent_dir_stats = {}

      assets.each do |path|
        parent_dir = extract_parent_directory(path)
        next unless parent_dir

        subdirectory_type = classify_subdirectory_type(path)
        next unless subdirectory_type

        parent_dir_stats[parent_dir] ||= { processed: 0, unprocessed: 0 }
        parent_dir_stats[parent_dir][subdirectory_type.to_sym] += 1
      end

      # Filter to only include directories where processed count equals unprocessed count
      # and both counts are > 0
      matching_dirs = parent_dir_stats.select do |parent_dir, counts|
        counts[:processed] > 0 &&
        counts[:unprocessed] > 0 &&
        counts[:processed] == counts[:unprocessed]
      end

      # Convert to the expected format
      matching_dirs.map do |parent_dir, counts|
        {
          parent_dir: parent_dir,
          processed_count: counts[:processed],
          unprocessed_count: counts[:unprocessed]
        }
      end
    end

    def build_base_tiff_query
      # Start with IsilonAsset, join to get volume info if needed
      query = IsilonAsset.joins(parent_folder: :volume)

      # Filter to only TIFF files
      query = query.where(
        "LOWER(file_type) LIKE ? OR LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?",
        "%tiff%", "%.tiff", "%.tif"
      )

      # Filter to deposit folders, excluding scrc accessions
      query = query.where("LOWER(isilon_path) LIKE ?", "%/deposit/%")
      query = query.where("LOWER(isilon_path) NOT LIKE ?", "%/deposit/scrc accessions%")

      # Filter to processed, unprocessed, or raw subdirectories
      query = query.where(
        "LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?",
        "%/processed/%", "%/unprocessed/%", "%/raw/%"
      )

      # Add volume filter if processing specific volume
      query = query.where(parent_folder: { volume: @parent_volume }) if @parent_volume

      query
    end

    def extract_parent_directory(path)
      # Extract the parent directory before /processed/, /unprocessed/, or /raw/
      case path.downcase
      when /^(.+)\/processed\//
        $1
      when /^(.+)\/unprocessed\//
        $1
      when /^(.+)\/raw\//
        $1
      else
        nil
      end
    end

    def classify_subdirectory_type(path)
      case path.downcase
      when /\/processed\//
        "processed"
      when /\/unprocessed\//, /\/raw\//
        "unprocessed"
      else
        nil
      end
    end

    def mark_unprocessed_tiffs_as_dont_migrate(parent_dir, count)
      dont_migrate_status = MigrationStatus.find_by(name: "Don't migrate")

      unless dont_migrate_status
        stdout_and_log("ERROR: 'Don't migrate' status not found", level: :error)
        return 0
      end

      # Build query for unprocessed TIFFs in this parent directory
      query = IsilonAsset.joins(parent_folder: :volume)
        .where("isilon_path LIKE ?", "#{parent_dir}/%")
        .where("(LOWER(isilon_path) LIKE '%/unprocessed/%' OR LOWER(isilon_path) LIKE '%/raw/%')")
        .where("(LOWER(file_type) LIKE '%tiff%' OR LOWER(isilon_path) LIKE '%.tiff' OR LOWER(isilon_path) LIKE '%.tif')")

      # Add volume filter if processing specific volume
      query = query.where(parent_folder: { volume: @parent_volume }) if @parent_volume

      updated_count = query.update_all(migration_status_id: dont_migrate_status.id)

      stdout_and_log("Rule 4: Marked #{updated_count} unprocessed TIFFs as 'Don't migrate' in #{parent_dir} (#{count} processed = #{count} unprocessed)")

      updated_count
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
