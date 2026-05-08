# frozen_string_literal: true

require "csv"
require "fileutils"
require "set"

module SyncService
  class ContentdmNonUniqueFilenameSync
    CONTENTDM_FILENAME_MATCH_NOTE = ContentdmFilenameSync::CONTENTDM_FILENAME_MATCH_NOTE
    SyncResult = Struct.new(
      :updated_count,
      :rows_touched,
      :rows_matched,
      :rows_unmatched,
      :rows_discarded,
      keyword_init: true
    )
    FILE_PATH = nil
    FILENAME_HEADER = "File Name"
    COLLECTION_HEADER = "Collection"
    NON_MATCHES_CSV_PATH = Rails.root.join("tmp", "contentdm_non_unique_filename_non_matches.csv")
    BATCH_SIZE = 500

    def self.call(file_path: FILE_PATH)
      new(file_path: file_path).sync
    end

    def initialize(file_path:)
      @file_path = file_path.to_s.strip.presence
    end

    def sync
      validate_file_path!
      filename_map, rows_touched = load_filename_map
      non_matches = []
      summary = {
        updated_count: 0,
        rows_touched: rows_touched,
        rows_matched: 0,
        rows_unmatched: 0,
        rows_discarded: 0
      }

      return SyncResult.new(**summary) if filename_map.empty?

      filename_map.each do |collection_name, entries|
        result = update_matching_assets(collection_name, entries, non_matches)
        summary[:updated_count] += result[:updated_count]
        summary[:rows_matched] += result[:rows_matched]
        summary[:rows_unmatched] += result[:rows_unmatched]
      end

      SyncResult.new(**summary)
    ensure
      write_non_matches_csv(non_matches || [])
    end

    private

    def load_filename_map
      rows_touched = 0
      filename_map = Hash.new { |hash, key| hash[key] = [] }

      CSV.foreach(@file_path, headers: true, liberal_parsing: true) do |row|
        original_path = row[FILENAME_HEADER].to_s.strip
        parent_folder_name, filename = split_parent_folder_and_filename(original_path)
        collection_name = normalize_collection_name(row[COLLECTION_HEADER])
        next if parent_folder_name.blank? || filename.blank? || collection_name.blank?

        rows_touched += 1
        filename_map[collection_name] << {
          parent_folder_name: parent_folder_name,
          normalized_filename: filename,
          original_filename: original_path
        }
      end

      [ filename_map, rows_touched ]
    end

    def validate_file_path!
      raise ArgumentError, "file_path is required" if @file_path.blank?
      raise ArgumentError, "CSV file not found: #{@file_path}" unless File.exist?(@file_path)
    end

    def split_parent_folder_and_filename(path)
      parent_folder_name, filename = path.to_s.split("/", 2)
      [
        normalize_value(parent_folder_name),
        normalize_value(filename)
      ]
    end

    def normalize_collection_name(collection_name)
      collection_name.to_s.strip.presence
    end

    def normalize_value(value)
      value.to_s.strip.downcase.presence
    end

    def update_matching_assets(collection_name, entries, non_matches)
      collection = find_collection!(collection_name)
      updated_count = 0
      rows_matched = 0
      rows_unmatched = 0

      entries.each_slice(BATCH_SIZE) do |entry_batch|
        matching_asset_ids, matched_entry_keys = matching_asset_ids(entry_batch)
        rows_matched += matched_entry_keys.size

        unmatched_entries = entry_batch.reject do |entry|
          matched_entry_keys.include?(entry_key(entry))
        end
        rows_unmatched += unmatched_entries.size
        non_matches.concat(
          unmatched_entries.map do |entry|
            {
              original_filename: entry[:original_filename],
              collection_name: collection_name
            }
          end
        )

        updated_count += IsilonAsset.where(id: matching_asset_ids.to_a).update_all(
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

    def matching_asset_ids(entry_batch)
      folder_names = entry_batch.map { |entry| entry[:parent_folder_name] }.uniq
      filenames = entry_batch.map { |entry| entry[:normalized_filename] }.uniq

      candidate_folders = candidate_folders_for(folder_names).select do |folder|
        folder_names.include?(folder_basename(folder.full_path))
      end
      folders_by_name = candidate_folders.group_by { |folder| folder_basename(folder.full_path) }

      candidate_parent_ids = candidate_folders.map(&:id)
      return [ Set.new, Set.new ] if candidate_parent_ids.empty?

      candidate_assets = IsilonAsset
        .includes(:parent_folder)
        .where(parent_folder_id: candidate_parent_ids)
        .where("LOWER(TRIM(isilon_name)) IN (?)", filenames)

      assets_by_key = candidate_assets.group_by do |asset|
        [ folder_basename(asset.parent_folder&.full_path), normalize_value(asset.isilon_name) ]
      end

      matched_asset_ids = Set.new
      matched_entry_keys = Set.new

      entry_batch.each do |entry|
        key = entry_key(entry)
        next unless folders_by_name[key.first].present?

        Array(assets_by_key[key]).each do |asset|
          matched_asset_ids << asset.id
          matched_entry_keys << key
        end
      end

      [ matched_asset_ids, matched_entry_keys ]
    end

    def candidate_folders_for(folder_names)
      clauses = []
      values = []

      folder_names.each do |folder_name|
        clauses << "(LOWER(full_path) = ? OR LOWER(full_path) LIKE ?)"
        values << "/#{folder_name}" << "%/#{folder_name}"
      end

      IsilonFolder.where(clauses.join(" OR "), *values)
    end

    def entry_key(entry)
      [ entry[:parent_folder_name], entry[:normalized_filename] ]
    end

    def folder_basename(full_path)
      full_path.to_s.split("/").reject(&:blank?).last.to_s.downcase.presence
    end

    def find_collection!(collection_name)
      ContentdmCollection.find_by!(name: collection_name)
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
