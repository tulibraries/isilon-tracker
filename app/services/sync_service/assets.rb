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
      @parent_volume_name = check_volume(@csv_path)
      stdout_and_log(%(Syncing assets from #{@csv_path}))
    end

    def sync
      imported = 0
      CSV.foreach(@csv_path, headers: true) do |row|
        asset = IsilonAsset.new(
          isilon_path:               row["Path"],
          isilon_name:               get_name(row["Path"]),
          file_size:                 row["Size"],
          file_type:                 row["Type"],
          file_checksum:             row["Hash"],
          last_modified_in_isilon:   row["ModifiedAt"],
          date_created_in_isilon:    row["CreatedAt"]
        )

        next if asset.isilon_path.count("/") < 4

        directory_check(asset)

        asset.parent_folder_id = get_parent_folder(asset.isilon_path)

        if asset.save!
          imported += 1
        else
          puts "Failed to import asset #{asset.isilon_path}: #{asset.errors.full_messages.join(", ")}"
        end
      end

      puts "Imported #{imported} IsilonAsset records."
    end

    def check_volume(path)
      first_row = CSV.read(path, headers: true).first
      volume = first_row["Path"].split("/").compact_blank[1]

      if Volume.exists?(name: volume)
        stdout_and_log("Volume #{volume} already exists.")
        volume
      else
        stdout_and_log("Creating volume: #{volume}")
        new_volume = Volume.create!(name: volume)
        new_volume.save!
        new_volume.name
      end
    end

    def get_name(path)
      path.split("/").last
    end

    def get_parent_folder(path)
      parent_path = "/" + path.split("/").compact_blank[0..-2].join("/")
      folder = IsilonFolder.find_or_create_by(full_path: parent_path)
      folder.volume_id = Volume.find_by(name: @parent_volume_name).id
      folder.save!
      folder.id
    end

    def directory_check(asset)
      directories = asset.isilon_path.split("/").compact_blank[0..-2]
      i = -2
      directories.each_with_index do |dir, index|
        i = i-index
        new_path = "/" + asset.isilon_path.split("/").compact_blank[0..i].join("/")
        parent_path = "/" + asset.isilon_path.split("/").compact_blank[0..i-1].join("/")
        next if new_path.count("/") < 3

        folder = IsilonFolder.find_or_create_by(full_path: new_path)
        stdout_and_log("Created or found folder: #{folder.full_path}")

        folder.volume_id = Volume.find_by(name: @parent_volume_name).id
        folder.parent_folder_id = get_parent_folder(parent_path)
        folder.save!
      end
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
