# frozen_string_literal: true

require "csv"
require "fileutils"

module SyncService
  class ContentdmFilenameSync
    CONTENTDM_FILENAME_MATCH_NOTE = "Filename exists in CONTENTdm"
    SyncResult = Struct.new(
      :updated_count,
      :rows_touched,
      :rows_matched,
      :rows_unmatched,
      :rows_discarded,
      keyword_init: true
    )
    CSV_FOLDER = nil
    FILENAME_HEADER = "File Name"
    COLLECTION_HEADER = "Collection"
    NON_MATCHES_CSV_PATH = Rails.root.join("tmp", "contentdm_filename_non_matches.csv")
    BATCH_SIZE = 500
    EXCLUDED_SOURCE_FILES = [ "scrc_manuscripts_non-unique_filenames.csv" ]
    CONFLICT_WINNERS = {
      [ "ambler_filenames.csv", "scrc_photographs_filenames.csv" ] => "ambler_filenames.csv",
      [ "bulletin_photos_filenames.csv", "bulletin_photos_restricted_filenames.csv" ] => "bulletin_photos_filenames.csv",
      [ "bulletin_photos_filenames.csv", "inquirer_filenames.csv" ] => "bulletin_photos_filenames.csv",
      [ "bulletin_photos_restricted_filenames.csv", "inquirer_filenames.csv" ] => "bulletin_photos_restricted_filenames.csv",
      [ "cityparks_filenames.csv", "hadv_filenames.csv" ] => "cityparks_filenames.csv",
      [ "inquirer_filenames.csv", "scrc_photographs_filenames.csv" ] => "inquirer_filenames.csv"
    }

    def self.call(csv_folder: CSV_FOLDER)
      new(csv_folder: csv_folder).sync
    end

    def initialize(csv_folder:)
      @csv_folder = csv_folder.to_s.strip.presence
    end

    def sync
      validate_csv_folder!
      csv_files = Dir.glob(File.join(@csv_folder, "*.csv")).sort.reject do |csv_path|
        EXCLUDED_SOURCE_FILES.include?(File.basename(csv_path))
      end
      raise ArgumentError, "No CSV files found in #{@csv_folder}" if csv_files.empty?

      load_result = load_filename_map(csv_files)
      filename_map = load_result[:filename_map]
      non_matches = []
      summary = {
        updated_count: 0,
        rows_touched: load_result[:rows_touched],
        rows_matched: 0,
        rows_unmatched: 0,
        rows_discarded: load_result[:rows_discarded]
      }

      if filename_map.empty?
        return SyncResult.new(**summary)
      end

      filename_map.each do |collection_name, filenames|
        result = update_matching_assets(collection_name, filenames, non_matches)
        summary[:updated_count] += result[:updated_count]
        summary[:rows_matched] += result[:rows_matched]
        summary[:rows_unmatched] += result[:rows_unmatched]
      end
      SyncResult.new(**summary)
    ensure
      write_non_matches_csv(non_matches || [])
    end

    private

    def load_filename_map(csv_files)
      filename_entries = Hash.new { |hash, key| hash[key] = [] }
      rows_touched = 0

      csv_files.each do |csv_path|
        raise ArgumentError, "CSV file not found: #{csv_path}" unless File.exist?(csv_path)

        source_file = File.basename(csv_path)
        CSV.foreach(csv_path, headers: true, liberal_parsing: true) do |row|
          original_filename = row[FILENAME_HEADER].to_s.strip
          filename = normalize_filename(original_filename)
          collection_name = normalize_collection_name(row[COLLECTION_HEADER])
          next if filename.blank? || collection_name.blank?
          rows_touched += 1

          filename_entries[filename] << {
            collection_name: collection_name,
            original_filename: original_filename,
            source_file: source_file
          }
        end
      end

      rows_discarded = 0
      filename_to_collection = filename_entries.each_with_object({}) do |(filename, entries), resolved|
        winner = entries.first
        entries.drop(1).each do |candidate_entry|
          winner = preferred_entry(filename, winner, candidate_entry)
        end
        rows_discarded += entries.size - 1
        resolved[filename] = winner
      end

      filename_map = filename_to_collection.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |(filename, entry), grouped|
        grouped[entry[:collection_name]] << {
          normalized_filename: filename,
          original_filename: entry[:original_filename]
        }
      end

      {
        filename_map: filename_map,
        rows_touched: rows_touched,
        rows_discarded: rows_discarded
      }
    end

    def validate_csv_folder!
      raise ArgumentError, "csv_folder is required" if @csv_folder.blank?

      raise ArgumentError, "CSV folder not found: #{@csv_folder}" unless Dir.exist?(@csv_folder)
    end

    def normalize_filename(filename)
      filename.to_s.strip.downcase.presence
    end

    def normalize_collection_name(collection_name)
      collection_name.to_s.strip.presence
    end

    def preferred_entry(filename, existing_entry, candidate_entry)
      return existing_entry if existing_entry[:collection_name] == candidate_entry[:collection_name]

      if existing_entry[:source_file] == candidate_entry[:source_file]
        raise ArgumentError,
              "Conflicting collections for filename '#{filename}' within #{existing_entry[:source_file]}: " \
              "'#{existing_entry[:collection_name]}' and '#{candidate_entry[:collection_name]}'"
      end

      winning_file = CONFLICT_WINNERS[[ existing_entry[:source_file], candidate_entry[:source_file] ].sort]
      if winning_file.blank?
        raise ArgumentError,
              "Conflicting collections for filename '#{filename}': '#{existing_entry[:collection_name]}' " \
              "(#{existing_entry[:source_file]}) and '#{candidate_entry[:collection_name]}' " \
              "(#{candidate_entry[:source_file]})"
      end

      winning_file == candidate_entry[:source_file] ? candidate_entry : existing_entry
    end

    def update_matching_assets(collection_name, filenames, non_matches)
      collection = find_collection!(collection_name)
      updated_count = 0
      rows_matched = 0
      rows_unmatched = 0

      filenames.each_slice(BATCH_SIZE) do |filename_batch|
        normalized_filenames = filename_batch.map { |entry| entry[:normalized_filename] }
        matched_filenames = matching_assets_scope(normalized_filenames)
          .distinct
          .pluck(Arel.sql("LOWER(TRIM(isilon_name))"))
        rows_matched += matched_filenames.size

        unmatched_entries = filename_batch.reject { |entry| matched_filenames.include?(entry[:normalized_filename]) }
        rows_unmatched += unmatched_entries.size
        non_matches.concat(
          unmatched_entries.map do |entry|
            {
              original_filename: entry[:original_filename],
              collection_name: collection_name
            }
          end
        )

        updated_count += matching_assets_scope(normalized_filenames).update_all(
          contentdm_collection_id: collection.id,
          notes: notes_update_sql,
          updated_at: Time.current
        )
      end

      {
        updated_count: updated_count,
        rows_matched: rows_matched,
        rows_unmatched: rows_unmatched
      }
    end

    def find_collection!(collection_name)
      ContentdmCollection.find_by!(name: collection_name)
    end

    def matching_assets_scope(filename_batch)
      IsilonAsset.where("LOWER(TRIM(isilon_name)) IN (?)", filename_batch)
    end

    def write_non_matches_csv(non_matches)
      FileUtils.mkdir_p(NON_MATCHES_CSV_PATH.dirname)

      CSV.open(NON_MATCHES_CSV_PATH, "w") do |csv|
        csv << [ FILENAME_HEADER, COLLECTION_HEADER ]

        non_matches.each do |entry|
          csv << [ entry[:original_filename], entry[:collection_name] ]
        end
      end
    end

    def notes_update_sql
      quoted_note = ActiveRecord::Base.connection.quote(CONTENTDM_FILENAME_MATCH_NOTE)
      contains_note_sql = note_contains_sql(quoted_note)

      Arel.sql(<<~SQL.squish)
        CASE
          WHEN notes IS NULL OR TRIM(notes) = '' THEN #{quoted_note}
          WHEN #{contains_note_sql} = 0 THEN notes || '; ' || #{quoted_note}
          ELSE notes
        END
      SQL
    end

    def note_contains_sql(quoted_note)
      if ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
        "strpos(notes, #{quoted_note})"
      else
        "instr(notes, #{quoted_note})"
      end
    end
  end
end
