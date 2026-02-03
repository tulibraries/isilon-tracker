# frozen_string_literal: true

require "csv"
require "logger"

module SyncService
  class AssetsRulesExport
    def self.call(output_path: nil)
      new(output_path:).export
    end

    def initialize(params = {})
      @output_path = params[:output_path].presence || default_output_path
      @log = Logger.new("log/isilon-sync-export.log")
      @missing_parent_log = Logger.new("log/isilon-assets-missing-parent.log")
      @stdout = Logger.new($stdout)
    end

    def export
      written = 0
      headers = [
        "Filename",
        "FullPath",
        "Rule",
        "WouldSetMigrationStatus"
      ]

      CSV.open(@output_path, "w", write_headers: true, headers: headers) do |out|
        assets_scope.find_each(batch_size: 1000) do |asset|
          volume_name = volume_name_from_parent(asset)
          full_path = build_full_path(volume_name, asset.isilon_path)
          rule_path = full_path.presence || asset.isilon_path.to_s
          result = migration_status_for(rule_path, volume_name)
          next unless result

          status_name, rule = result
          @log.info("Rule #{rule} would set migration_status to '#{status_name}' for #{rule_path} (asset_id=#{asset.id})")

          out << [
            asset.isilon_name,
            full_path,
            rule,
            status_name
          ]
          written += 1
        end
      end

      stdout_and_log("Wrote #{written} assets to #{@output_path}")
    end

    private

    def default_output_path
      "log/isilon-asset-rules-export.csv"
    end

    def assets_scope
      IsilonAsset.left_joins(parent_folder: :volume).preload(parent_folder: :volume)
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

    def build_full_path(volume_name, isilon_path)
      return nil if volume_name.blank?

      path = isilon_path.to_s
      path = "/#{path}" unless path.start_with?("/")
      "/#{volume_name}#{path}".gsub(%r{//+}, "/")
    end

    def migration_status_for(asset_path, volume_name)
      return [ "Migrated", 1 ] if rule_1_migrated_directory?(asset_path)
      return [ "Don't migrate", 2 ] if rule_2_delete_directory?(asset_path, volume_name)

      nil
    end

    def rule_1_migrated_directory?(asset_path)
      return false unless asset_path.downcase.include?("/deposit/")
      return false if asset_path.downcase.include?("/deposit/scrc accessions")

      path_segments = asset_path.split("/")
      path_segments.any? { |segment| segment.downcase.include?("- migrated") }
    end

    def rule_2_delete_directory?(asset_path, volume_name)
      return false unless volume_name&.casecmp?("deposit")

      segments = asset_path.split("/").reject(&:blank?)
      return false if segments.empty?

      segments.shift

      return false unless segments.any? { |segment| segment.casecmp?("scrc accessions") }

      segments.any? { |segment| segment.downcase.include?("delete") }
    end

    def stdout_and_log(message, level: :info)
      @log.send(level, message)
      @stdout.send(level, message)
    end
  end
end
