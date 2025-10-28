# frozen_string_literal: true

require "csv"
require "logger"

module SyncService
  class Assets
    def self.call(csv_path: nil)
      new(csv_path:).sync
    end

    def initialize(params = {})
      @csv_path = params.fetch(:csv_path)
      @log = Logger.new("log/isilon-sync.log")
      @stdout = Logger.new($stdout)
      @parent_volume = check_volume(@csv_path)
      @default_status = MigrationStatus.find_by(default: true) || stdout_and_log("No default migration_status found. Please ensure one exists with default: true.")
      stdout_and_log(%(Syncing assets from #{@csv_path}))
    end

    def sync
      imported = 0
      batch_size = 100

      stdout_and_log("Starting CSV processing with batch size: #{batch_size}")

      # Process CSV in batches for better memory management
      CSV.open(@csv_path, "r", headers: true, liberal_parsing: true) do |csv|
        csv.lazy.each_slice(batch_size) do |batch|
          batch_imported = process_batch(batch)
          imported += batch_imported
          stdout_and_log("Processed batch: #{batch_imported} assets imported (Total: #{imported})")

          # Trigger garbage collection periodically to manage memory
          GC.start if imported % (batch_size * 5) == 0
        end
      end

      stdout_and_log("Imported #{imported} IsilonAsset records.")
    end

    private

    def process_batch(batch)
      assets_to_create = []
      batch_imported = 0

      batch.each do |row|
        next if row["Path"].include?(".DS_Store") || row["Path"].include?("thumbs.db") || row["Path"].include?(".apdisk")

        # Ensure directory structure exists before bulk insert
        isilon_path = set_full_path(row["Path"])

        if ensure_directory_structure(isilon_path)
          begin
            parent_folder_id = get_asset_parent_id(row["Path"].split("/").compact_blank[1...-1])&.id

            assets_to_create << {
              isilon_path: isilon_path,
              isilon_name: get_name(row["Path"]),
              file_size: row["Size"],
              file_type: row["Type"],
              file_checksum: row["Hash"],
              last_modified_in_isilon: row["ModifiedAt"],
              date_created_in_isilon: row["CreatedAt"],
              parent_folder_id: parent_folder_id,
              migration_status_id: apply_automation_rules(row) || @default_status&.id,
              created_at: Time.current,
              updated_at: Time.current
            }
          rescue => e
            stdout_and_log("Failed to prepare asset #{isilon_path}: #{e.message}", level: :error)
          end
        else
          stdout_and_log("Skipping asset with invalid path: #{isilon_path}", level: :error)
        end
      end

      # Bulk insert all valid assets at once
      if assets_to_create.any?
        begin
          IsilonAsset.insert_all(assets_to_create)
          batch_imported = assets_to_create.size
          stdout_and_log("Bulk inserted #{batch_imported} assets")
        rescue => e
          stdout_and_log("Bulk insert failed, falling back to individual saves: #{e.message}", level: :error)
          batch_imported = fallback_individual_saves(assets_to_create)
        end
      end

      batch_imported
    end

    def ensure_directory_structure(isilon_path)
      all_directories = isilon_path.split("/").compact_blank
      directories = all_directories[0...-1]
      return false if directories.empty?

      volume = Volume.find_by(name: @parent_volume.name)

      (directories.size).downto(0) do |i|
        if directories.present?
          parent_folder = get_folder_parent_id(directories)
          current_path = "/" + directories.join("/")

          begin
            folder = find_or_create_folder_safely(volume.id, current_path)
            folder.update!(parent_folder_id: parent_folder.id) if parent_folder.present?
          rescue => e
            stdout_and_log("Unable to create or find folder: #{current_path}; #{e.message}", level: :error)
            return false
          end

          directories.pop unless i == 0
        end
      end

      true
    end

    def fallback_individual_saves(assets_to_create)
      saved_count = 0

      assets_to_create.each do |asset_attrs|
        begin
          # Remove bulk insert timestamps and let Rails handle them
          asset_attrs.delete(:created_at)
          asset_attrs.delete(:updated_at)

          asset = IsilonAsset.new(asset_attrs)
          if asset.save!
            saved_count += 1
          end
        rescue => e
          stdout_and_log("Failed to save individual asset #{asset_attrs[:isilon_path]}: #{e.message}", level: :error)
        end
      end

      saved_count
    end

    def set_full_path(path)
      volume_segment = [ "/", @parent_volume.name ].join
      path.gsub(volume_segment, "")
    end

    def check_volume(path)
      first_row = CSV.read(path, headers: true).first
      volume = first_row["Path"].split("/").compact_blank[0]

      if Volume.exists?(name: volume)
        stdout_and_log("Volume #{volume} already exists.")
        Volume.find_by(name: volume)
      else
        new_volume = Volume.create!(name: volume)
        begin
          new_volume.save!
          stdout_and_log("Created new volume: #{new_volume.name}")
        rescue => e
          stdout_and_log("Unable to save volume: #{volume}; #{e.message}", level: :error)
        end
        new_volume
      end
    end

    def get_folder_parent_id(path)
      path = path[0...-1]
      path = path.join("/")
      return nil unless path.present?

      find_or_create_folder_safely(@parent_volume.id, "/#{path}")
    end

    def get_asset_parent_id(path)
      path = path.join("/")
      return nil unless path.present?

      find_or_create_folder_safely(@parent_volume.id, "/#{path}")
    end

    def find_or_create_folder_safely(volume_id, full_path)
      retry_count = 0
      max_retries = 3

      begin
        IsilonFolder.find_or_create_by!(volume_id: volume_id, full_path: full_path)
      rescue ActiveRecord::RecordNotUnique
        retry_count += 1
        if retry_count <= max_retries
          # Brief backoff to avoid thundering herd
          sleep(0.1 * retry_count)

          # Try to find the existing folder
          existing_folder = IsilonFolder.find_by(volume_id: volume_id, full_path: full_path)
          return existing_folder if existing_folder

          # If we still can't find it, retry the create
          retry if retry_count <= max_retries
        end

        raise ActiveRecord::RecordNotFound, "Could not find or create folder after #{max_retries} retries: #{full_path}"
      end
    end

    def get_name(path)
      path.split("/").last
    end

    def apply_automation_rules(row)
      # AUTOMATION RULES SUMMARY:
      # Rule 1: Migrated directories in deposit (but not born-digital) -> "Migrated"
      # Rule 2: DELETE directories in born-digital deposit areas -> "Don't migrate"
      # Rule 3: Duplicate detection -> Handled by separate post-processing task
      # Rule 4: Unprocessed/raw files when processed equivalents exist -> "Don't migrate" (post-processing)

      asset_path = row["Path"]
      return nil unless asset_path

      # Rule 1: Migrated directories in deposit (but not born-digital)
      if rule_1_migrated_directory?(asset_path)
        stdout_and_log("Rule 1 applied: Migrated directory detected for #{asset_path}")
        return MigrationStatus.find_by(name: "Migrated")&.id
      end

      # Rule 2: DELETE directories in born-digital deposit areas
      if rule_2_delete_directory?(asset_path)
        stdout_and_log("Rule 2 applied: DELETE directory detected for #{asset_path}")
        return MigrationStatus.find_by(name: "Don't migrate")&.id
      end

      # Rule 3: Handled by separate duplicate detection task: https://tulibdev.atlassian.net/browse/IMT-142
      # Rule 4: Handled entirely in post-processing for accurate TIFF count comparison

      nil # No automation rule applies
    end

    private

    def rule_1_migrated_directory?(asset_path)
      # Directory is in deposit AND contains "- Migrated" AND NOT in born-digital area
      return false unless asset_path.downcase.include?("/deposit/")
      return false if asset_path.downcase.include?("/deposit/scrc accessions")

      # Check if the path or any parent directory contains "- migrated"
      path_segments = asset_path.split("/")
      path_segments.any? { |segment| segment.downcase.include?("- migrated") }
    end

    def rule_2_delete_directory?(asset_path)
      return false unless @parent_volume&.name&.casecmp?("deposit")

      segments = asset_path.split("/").reject(&:blank?)
      return false if segments.empty?

      # Ignore the volume segment; CSVs always start with it.
      segments.shift

      return false unless segments.any? { |segment| segment.casecmp?("scrc accessions") }

      segments.any? { |segment| segment.downcase.include?("delete") }
    end



    def stdout_and_log(message, level: :info)
      # Toggle for batch processing visibility
      return unless level == :error

      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
