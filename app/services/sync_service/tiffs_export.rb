# frozen_string_literal: true

require "csv"
require "logger"
require "ostruct"

module SyncService
  class TiffsExport
    def self.call(volume_name: nil, output_path: nil)
      new(volume_name:, output_path:).export
    end

    ALLOWED_VOLUME_NAMES = %w[Deposit Media-Repository].freeze
    ROOT_CHILD_KEY = "__root__".freeze

    def initialize(volume_name: nil, output_path: nil)
      @volume_name = volume_name
      @output_path = output_path.presence || default_output_path
      @log = Logger.new("log/isilon-tiffs-export.log")
      @missing_parent_log = Logger.new("log/isilon-tiffs-missing-parent.log")
      @stdout = Logger.new($stdout)

      if @volume_name
        validate_volume_name!(@volume_name)
        @parent_volume = find_volume_case_insensitive(@volume_name)
        raise ArgumentError, "Volume '#{@volume_name}' not found" unless @parent_volume
        @volume_name = @parent_volume.name
      else
        @parent_volume = nil
      end
    end

    def export
      parent_dirs_with_counts = find_parent_dirs_with_matching_tiff_counts_ar
      stdout_and_log("Found #{parent_dirs_with_counts.size} parent directories with matching TIFF counts")

      headers = [ "FullPath" ]

      written = 0
      CSV.open(@output_path, "w", write_headers: true, headers: headers) do |out|
        parent_dirs_with_counts.each do |parent_info|
          assets_for_match(parent_info).find_each(batch_size: 1000) do |asset|
            volume_name = volume_name_from_parent(asset)
            full_path = build_full_path(volume_name, asset.isilon_path)
            next if full_path.blank?

            out << [ full_path ]
            written += 1
          end
        end
      end

      stdout_and_log("Wrote #{written} assets to #{@output_path}")
    end

    private

    def default_output_path
      "log/isilon-tiffs-export.csv"
    end

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

    def assets_for_match(parent_info)
      patterns =
        if parent_info[:child_key] == ROOT_CHILD_KEY
          [
            "#{parent_info[:parent_key]}/unprocessed/%",
            "#{parent_info[:parent_key]}/raw/%"
          ]
        else
          [
            "#{parent_info[:parent_key]}/unprocessed/#{parent_info[:child_key]}/%",
            "#{parent_info[:parent_key]}/raw/#{parent_info[:child_key]}/%"
          ]
        end

      query = IsilonAsset.joins(parent_folder: :volume)
        .where(
          "(LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?)",
          *patterns
        )
        .where("(LOWER(file_type) LIKE '%tiff%' OR LOWER(isilon_path) LIKE '%.tiff' OR LOWER(isilon_path) LIKE '%.tif')")

      query = query.where(parent_folder: { volume: @parent_volume }) if @parent_volume
      query
    end

    def build_base_tiff_query
      query = IsilonAsset.joins(parent_folder: :volume)

      query = query.where(
        "LOWER(file_type) LIKE ? OR LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?",
        "%tiff%", "%.tiff", "%.tif"
      )

      query = query.where("LOWER(isilon_path) NOT LIKE ?", "%/scrc accessions/%")

      query = query.where(
        "LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ? OR LOWER(isilon_path) LIKE ?",
        "%/processed/%", "%/unprocessed/%", "%/raw/%"
      )

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

    def build_full_path(volume_name, isilon_path)
      return nil if volume_name.blank?

      path = isilon_path.to_s
      path = "/#{path}" unless path.start_with?("/")
      "/#{volume_name}#{path}".gsub(%r{//+}, "/")
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end

    def volume_name_from_parent(asset)
      parent = asset.parent_folder
      unless parent
        log_missing_parent(asset, reason: "missing_parent_folder")
        return nil
      end

      volume = parent.volume
      unless volume
        log_missing_parent(asset, reason: "missing_parent_volume")
        return nil
      end

      volume.name
    end

    def log_missing_parent(asset, reason:)
      @missing_parent_log.info(
        "Skipped volume lookup (#{reason}) for asset_id=#{asset.id} isilon_path=#{asset.isilon_path}"
      )
    end

    def validate_volume_name!(name)
      return if ALLOWED_VOLUME_NAMES.any? { |allowed| allowed.casecmp?(name.to_s) }

      allowed_display = ALLOWED_VOLUME_NAMES.join(", ")
      raise ArgumentError, "Volume '#{name}' is not supported. Use one of: #{allowed_display}"
    end

    def find_volume_case_insensitive(name)
      Volume.where("LOWER(name) = ?", name.to_s.downcase).first
    end
  end
end
