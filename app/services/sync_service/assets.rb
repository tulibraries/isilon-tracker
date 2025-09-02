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
      CSV.foreach(@csv_path, headers: true) do |row|
        next if row["Path"].include?(".DS_Store") # putting this here prevents empty folders
        asset = IsilonAsset.new(
          isilon_path:               set_full_path(row["Path"]),
          isilon_name:               get_name(row["Path"]),
          file_size:                 row["Size"],
          file_type:                 row["Type"],
          file_checksum:             row["Hash"],
          last_modified_in_isilon:   row["ModifiedAt"],
          date_created_in_isilon:    row["CreatedAt"],
          parent_folder_id:          get_asset_parent_id(row["Path"].split("/").compact_blank[1...-1]).id,
          migration_status_id:       @default_status&.id
        )

        if directory_check(asset)
          begin
            imported += 1 if asset.save!
          rescue => e
            stdout_and_log("Failed to import asset #{asset.isilon_path}: #{e.message}", level: :error)
          end
        else
          stdout_and_log("Skipping asset with invalid path: #{asset.isilon_path}", level: :error)
        end
      end

      stdout_and_log("Imported #{imported} IsilonAsset records.")
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

    def directory_check(asset)
      all_directories = asset.isilon_path.split("/").compact_blank
      directories = all_directories[0...-1]
      return if directories.empty?
      volume = Volume.find_by(name: @parent_volume.name)

      (directories.size).downto(0) do |i|
        if directories.present?
          parent_folder = get_folder_parent_id(directories)
          current_path = "/" + directories.join("/")

          folder = IsilonFolder.find_or_create_by!(volume_id: volume.id, full_path: current_path)
          folder.update!(parent_folder_id: parent_folder.id) if parent_folder.present?
          directories.pop unless i == 0

          begin
            folder.save!
          rescue => e
            stdout_and_log("Unable to save folder: #{current_path}; #{e.message}", level: :error)
          end
        end
      end
    end

    def get_folder_parent_id(path)
      path = path[0...-1]
      path = path.join("/")
      IsilonFolder.find_or_create_by!(volume_id: @parent_volume.id, full_path: "/#{path}") if path.present?
    end

    def get_asset_parent_id(path)
      path = path.join("/")
      IsilonFolder.find_or_create_by!(volume_id: @parent_volume.id, full_path: "/#{path}") if path.present?
    end

    def get_name(path)
      path.split("/").last
    end

    def stdout_and_log(message, level: :info)
      return unless level == :error

      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
