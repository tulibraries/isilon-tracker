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
        if asset.save!
          imported += 1
        else
          puts "Failed to import asset #{asset.isilon_path}: #{asset.errors.full_messages.join(", ")}"
        end
      end

      puts "Imported #{imported} IsilonAsset records."
    end

    def get_name(path)
      path.split("/").last
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
