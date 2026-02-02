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
              full_isilon_path: full_path_with_volume(row["Path"]),
              file_size: row["Size"],
              file_type: row["Type"],
              file_checksum: row["Hash"],
              last_modified_in_isilon: row["ModifiedAt"],
              date_created_in_isilon: row["CreatedAt"],
              parent_folder_id: parent_folder_id,
              migration_status_id: @default_status&.id,
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
      return true if directories.empty?

      volume = @parent_volume

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
      segments = path.to_s.split("/").reject(&:blank?)
      return "/" if segments.size <= 1

      "/" + segments[1..].join("/")
    end

    def full_path_with_volume(path)
      segments = path.to_s.split("/").reject(&:blank?)
      return "/" if segments.empty?

      "/" + segments.join("/")
    end

    def check_volume(path)
      first_row = CSV.read(path, headers: true).first
      volume = first_row["Path"].split("/").compact_blank[0]

      existing_volume = find_volume_case_insensitive(volume)

      if existing_volume
        stdout_and_log("Volume #{existing_volume.name} already exists.")
        existing_volume
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

    def find_volume_case_insensitive(name)
      Volume.where("LOWER(name) = ?", name.to_s.downcase).first
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

    def stdout_and_log(message, level: :info)
      # Toggle for batch processing visibility
      return unless level == :error

      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
