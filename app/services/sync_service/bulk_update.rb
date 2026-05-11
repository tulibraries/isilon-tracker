# frozen_string_literal: true

module SyncService
  class BulkUpdate
    BATCH_SIZE = 10_000

    Result = Struct.new(
      :updated_count,
      :asset_updated_count,
      :folder_updated_count,
      :folder_count,
      :volume_id,
      :full_path,
      keyword_init: true
    )

    def self.call(volume_id:, full_path:, updates: {})
      new(volume_id: volume_id, full_path: full_path, updates: updates).call
    end

    def initialize(volume_id:, full_path:, updates:)
      @volume_id = volume_id
      @full_path = full_path.to_s.strip
      @updates = updates
    end

    def call
      validate_updates!

      folder = IsilonFolder.find_by!(volume_id: @volume_id, full_path: @full_path)
      descendant_folder_ids = descendant_folder_ids_for(folder.id)
      asset_updates = asset_update_attributes
      folder_updates = folder_update_attributes
      asset_updated_count = 0
      folder_updated_count = 0

      if asset_updates.any?
        IsilonAsset.where(parent_folder_id: descendant_folder_ids).in_batches(of: BATCH_SIZE) do |batch|
          asset_updated_count += batch.update_all(asset_updates)
        end
      end

      if folder_updates.any?
        IsilonFolder.where(id: descendant_folder_ids).in_batches(of: BATCH_SIZE) do |batch|
          folder_updated_count += batch.update_all(folder_updates)
        end
      end

      Result.new(
        updated_count: asset_updated_count + folder_updated_count,
        asset_updated_count: asset_updated_count,
        folder_updated_count: folder_updated_count,
        folder_count: descendant_folder_ids.length,
        volume_id: folder.volume_id,
        full_path: folder.full_path
      )
    end

    private

    def validate_updates!
      return if @updates.present?

      raise ArgumentError, "At least one update field is required"
    end

    def asset_update_attributes
      {}.tap do |updates|
        updates[:migration_status_id] = validated_migration_status_id if @updates.key?(:migration_status_id)
        updates[:assigned_to_id] = validated_assigned_to_id if @updates.key?(:assigned_to_id)
      end
    end

    def folder_update_attributes
      {}.tap do |updates|
        updates[:assigned_to_id] = validated_assigned_to_id if @updates.key?(:assigned_to_id)
      end
    end

    def validated_migration_status_id
      return nil if @updates[:migration_status_id].nil?

      MigrationStatus.find(@updates[:migration_status_id]).id
    end

    def validated_assigned_to_id
      return nil if @updates[:assigned_to_id].nil?

      User.find(@updates[:assigned_to_id]).id
    end

    def descendant_folder_ids_for(folder_id)
      sql = <<~SQL.squish
        WITH RECURSIVE descendants AS (
          SELECT id
          FROM isilon_folders
          WHERE id = #{folder_id.to_i} AND volume_id = #{@volume_id.to_i}
          UNION ALL
          SELECT child.id
          FROM isilon_folders child
          INNER JOIN descendants parent_descendants ON child.parent_folder_id = parent_descendants.id
          WHERE child.volume_id = #{@volume_id.to_i}
        )
        SELECT id FROM descendants
      SQL

      ActiveRecord::Base.connection.exec_query(sql).rows.flatten.map(&:to_i).uniq
    end
  end
end
