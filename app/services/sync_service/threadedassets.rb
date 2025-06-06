# frozen_string_literal: true

require "csv"
require "logger"

module SyncService
  class Threadedassets
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
      threads = []
      max_threads = 5
      mutex = Mutex.new # Create a Mutex for thread-safe operations, neccessary for ruby 3.0+

      CSV.foreach(@csv_path, headers: true).each_slice(100) do |rows|
        threads << Thread.new(rows) do |batch|
          batch.each do |row|
            begin
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
              next if :isilon_name == ".DS_Store"

              directory_check(asset)

              asset.parent_folder_id = get_parent_folder(asset.isilon_path)
              stdout_and_log("Processing asset: #{asset.isilon_path}")
              if asset.save!
                mutex.synchronize { imported += 1 }
              else
                stdout_and_log("Failed to import asset #{asset.isilon_path}: #{asset.errors.full_messages.join(", ")}")
              end
            rescue => e
              stdout_and_log("Error processing row: #{e.message}", level: :error)
            end
          end
        end

        # Limit the number of threads
        # threads.select!(&:alive?) while threads.size >= max_threads
        threads.select! do |thread|
          if thread.alive?
            true
          else
            stdout_and_log("Thread #{thread.object_id} has finished.")
            false
          end
        end while threads.size >= max_threads
      end

        # Wait for all threads to finish
        threads.each(&:join)

        puts "Imported #{imported} IsilonAsset records."
        stdout_and_log("Imported #{imported} IsilonAsset records.")
    end

    def check_volume(path)
      first_row = CSV.read(path, headers: true).first
      volume = first_row["Path"].split("/").compact_blank[0]

      if Volume.exists?(name: volume)
        volume
      else
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
        parent_path = "/" + asset.isilon_path.split("/").compact_blank[0..i].join("/")
        next if new_path.count("/") < 3

        folder = IsilonFolder.find_or_create_by(full_path: new_path)

        folder.volume_id = Volume.find_by(name: @parent_volume_name).id
        folder.parent_folder_id = get_parent_folder(parent_path)

        unless folder.save!
          stdout_and_log "Failed to create folder #{folder.full_path}: #{folder.errors.full_messages.join(", ")}"
        end
      end
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
