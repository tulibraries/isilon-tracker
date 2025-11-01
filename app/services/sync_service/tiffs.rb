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
      else
        @parent_volume = nil  # Will process all volumes
      end
    end

    def process
      begin
        # Use ActiveRecord to find parent directories with matching TIFF counts
        parent_dirs_with_counts = find_parent_dirs_with_matching_tiff_counts_ar

        stdout_and_log("Found #{parent_dirs_with_counts.size} parent directories with matching TIFF counts")

        # Update unprocessed TIFFs in bulk
        total_updated = 0
        parent_dirs_with_counts.each do |parent_info|
          updated = mark_unprocessed_tiffs_as_dont_migrate(
            parent_info[:parent_dir],
            parent_info[:child_folder],
            parent_info[:child_key],
            parent_info[:parent_key],
            parent_info[:processed_count]
          )
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

    ROOT_CHILD_KEY = "__root__".freeze

    def find_parent_dirs_with_matching_tiff_counts_ar
      base_query = build_base_tiff_query
      assets = base_query.pluck(:isilon_path)

      stats = Hash.new do |hash, parent_key|
        hash[parent_key] = {
          original_parent: nil,
          processed: Hash.new { |child_hash, key| child_hash[key] = { count: 0, name: nil } },
          unprocessed: Hash.new { |child_hash, key| child_hash[key] = { count: 0, name: nil } }
        }
      end

      assets.each do |path|
        parent_dir, child_folder, category = extract_parent_child_and_category(path)
        next unless parent_dir && category

        parent_key = parent_dir.downcase
        record = stats[parent_key]
        record[:original_parent] ||= parent_dir

        child_key = (child_folder || ROOT_CHILD_KEY).downcase
        bucket = category == :processed ? :processed : :unprocessed
        entry = record[bucket][child_key]
        entry[:count] += 1
        entry[:name] ||= child_folder
      end

      matches = []

      stats.each do |parent_key, record|
        processed_children = record[:processed]
        next if processed_children.empty?

        processed_children.each do |child_key, processed_entry|
          unprocessed_entry = record[:unprocessed][child_key]
          next unless unprocessed_entry[:count].positive?

          original_parent = record[:original_parent] || parent_key
          child_display = processed_entry[:name] || unprocessed_entry[:name]

          next unless processed_entry[:count] == unprocessed_entry[:count]

          log_tiff_directory(
            original_parent,
            child_display,
            processed_entry[:count],
            unprocessed_entry[:count]
          )

          matches << {
            parent_dir: original_parent,
            parent_key: parent_key,
            child_folder: child_display,
            child_key: child_key,
            processed_count: processed_entry[:count],
            unprocessed_count: unprocessed_entry[:count]
          }
        end
      end

      matches
    end

    def build_base_tiff_query
      # Start with IsilonAsset, join to get volume info if needed
      query = IsilonAsset.joins(parent_folder: :volume)

      # Filter to only TIFF files
      query = query.where(
        "LOWER(file_type) LIKE ? OR LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?",
        "%tiff%", "%.tiff", "%.tif"
      )

      # Exclude SCRC Accessions regardless of volume prefix stripping
      query = query.where("LOWER(isilon_path) NOT LIKE ?", "%/scrc accessions/%")

      # Filter to processed, unprocessed, or raw subdirectories
      query = query.where(
        "LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?",
        "%/processed/%", "%/unprocessed/%", "%/raw/%"
      )

      # Add volume filter if processing specific volume
      query = query.where(parent_folder: { volume: @parent_volume }) if @parent_volume

      query
    end

    def extract_parent_child_and_category(path)
      segments = path.split("/")
      key_index = segments.index { |segment| %w[processed unprocessed raw].include?(segment&.downcase) }
      return nil unless key_index

      parent_segments = segments[0...key_index]
      parent_dir = parent_segments.join("/")
      parent_dir = "/#{parent_dir}".gsub(%r{//+}, "/")
      parent_dir = "/" if parent_dir.blank?
      parent_dir = parent_dir.downcase

      remainder = segments[(key_index + 1)..]
      child_folder = if remainder && remainder.length > 1
                       remainder.first.downcase
      else
                       nil
      end

      category = segments[key_index].downcase == "processed" ? :processed : :unprocessed

      [ parent_dir, child_folder, category ]
    end

    def mark_unprocessed_tiffs_as_dont_migrate(parent_dir, child_folder, child_key, parent_key, count)
      dont_migrate_status = MigrationStatus.find_by(name: "Don't migrate")

      unless dont_migrate_status
        stdout_and_log("ERROR: 'Don't migrate' status not found", level: :error)
        return 0
      end

      patterns =
        if child_key == ROOT_CHILD_KEY
          [
            "#{parent_key}/unprocessed/%",
            "#{parent_key}/raw/%"
          ]
        else
          [
            "#{parent_key}/unprocessed/#{child_key}/%",
            "#{parent_key}/raw/#{child_key}/%"
          ]
        end

      query = IsilonAsset.joins(parent_folder: :volume)
        .where(
          "(LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?)",
          *patterns
        )
        .where("(LOWER(file_type) LIKE '%tiff%' OR LOWER(isilon_path) LIKE '%.tiff' OR LOWER(isilon_path) LIKE '%.tif')")

      # Add volume filter if processing specific volume
      query = query.where(parent_folder: { volume: @parent_volume }) if @parent_volume

      updated_count = query.update_all(migration_status_id: dont_migrate_status.id)

      stdout_and_log(
        "Rule 4: Marked #{updated_count} unprocessed TIFFs as 'Don't migrate' in #{parent_dir}/(#{child_folder || 'root'}) "\
        "(#{count} processed = #{count} unprocessed)"
      )

      updated_count
    end

    def extract_parent_directory(path)
      extract_parent_child_and_category(path)&.first
    end

    def classify_subdirectory_type(path)
      _, _, category = extract_parent_child_and_category(path)
      return nil unless category

      category == :processed ? "processed" : "unprocessed"
    end

    def log_tiff_directory(parent_dir, child_folder, processed_count, unprocessed_count)
      # intentionally suppressed verbose candidate logging
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
