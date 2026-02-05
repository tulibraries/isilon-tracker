class BatchActionsController < ApplicationController
  before_action :set_volume
  BATCH_UPDATE_SIZE = 10_000

  def update
    asset_ids = params[:asset_ids].to_s.split(",").map(&:to_i).reject(&:zero?)
    folder_ids = params[:folder_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if asset_ids.empty? && folder_ids.empty?
      redirect_to @volume, alert: "No assets or folders selected for batch update."
      return
    end

    updated_count = 0
    updates_applied = []

    begin
      ActiveRecord::Base.transaction do
        # Process assets if any are selected
        if asset_ids.any?
          assets = @volume.isilon_assets.where(id: asset_ids)
          if assets.any?
            updated_count += process_asset_updates(assets, updates_applied)
          end
        end

        # Process folders if any are selected
        if folder_ids.any?
          folders = @volume.isilon_folders.where(id: folder_ids)
          if folders.any?
            updated_count += process_folder_updates(folders, updates_applied)
          end
        end
      end

      # Check for no updates after transaction completes
      if updated_count == 0
        redirect_to @volume, alert: "No valid assets or folders found for batch update."
        return
      end
    rescue StandardError => e
      Rails.logger.error "Batch action error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      error_message = "An error occurred while updating: #{e.message}"

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-messages",
            partial: "shared/flash_message",
            locals: { message: error_message, type: "error" }
          )
        end
        format.html { redirect_to @volume, alert: error_message }
      end
      return
    end

    if updates_applied.any?
      success_message = "Successfully updated #{updated_count} item#{'s' if updated_count != 1}: #{updates_applied.join(', ')}"

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-messages",
            partial: "shared/flash_message",
            locals: { message: success_message, type: "success" }
          )
        end
        format.html { redirect_to @volume, notice: success_message }
      end
    else
      no_changes_message = "Batch update completed successfully. No changes were made."

      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.update("flash-messages",
            partial: "shared/flash_message",
            locals: { message: no_changes_message, type: "info" }
          )
        end
        format.html { redirect_to @volume, notice: no_changes_message }
      end
    end
  end

  private

  def set_volume
    @volume = Volume.find(params[:volume_id])
  end

  def process_asset_updates(assets, updates_applied)
    updates = {}

    # Update Migration Status
    if params[:migration_status_id].present?
      migration_status = MigrationStatus.find(params[:migration_status_id])
      updates[:migration_status_id] = migration_status.id
      updates_applied << "migration status to #{migration_status.name}"
    end

    # Update Assigned User
    if params[:assigned_user_id].present?
      if params[:assigned_user_id] == "unassigned"
        updates[:assigned_to] = nil
        updates_applied << "assigned user to unassigned"
      else
        user = User.find(params[:assigned_user_id])
        updates[:assigned_to] = user.id
        updates_applied << "assigned user to #{user.title}"
      end
    end

    # Update ASpace Collection
    if params[:aspace_collection_id].present?
      aspace_collection = AspaceCollection.find(params[:aspace_collection_id])
      updates[:aspace_collection_id] = aspace_collection.id
      updates_applied << "ASpace collection to #{aspace_collection.name}"
    end

    # Update ASpace Linking Status
    if params[:aspace_linking_status].present? && params[:aspace_linking_status] != ""
      linking_status = params[:aspace_linking_status]
      updates[:aspace_linking_status] = linking_status
      status_text = linking_status == "true" ? "linked" : "not linked"
      updates_applied << "ASpace linking status to #{status_text}"
    end

    assets_count = assets.count
    return 0 if assets_count == 0

    if updates.any?
      assets.in_batches(of: BATCH_UPDATE_SIZE) do |batch|
        batch.update_all(updates)
      end
    end

    assets_count
  end

  def process_folder_updates(folders, updates_applied)
    updated_count = 0

    # Only assigned_to is supported for folders currently
    if params[:assigned_user_id].present?
      user = nil
      if params[:assigned_user_id] != "unassigned"
        user = User.find(params[:assigned_user_id])
      end

      folder_ids = folder_ids_with_descendants(folders.pluck(:id))
      if folder_ids.any?
        folder_ids.each_slice(BATCH_UPDATE_SIZE) do |batch_ids|
          IsilonFolder.where(id: batch_ids).update_all(assigned_to: user&.id)
        end
        updated_count += folder_ids.length
      end

      updates_applied << "assigned folders to #{user ? user.title : 'unassigned'}"
    end

    updated_count
  end

  def folder_ids_with_descendants(folder_ids)
    ids = folder_ids.map(&:to_i).reject(&:zero?).uniq
    return [] if ids.empty?

    volume_id = @volume.id

    sql = <<~SQL.squish
      WITH RECURSIVE descendants AS (
        SELECT id FROM isilon_folders
        WHERE id IN (#{ids.join(",")}) AND volume_id = #{volume_id}
        UNION ALL
        SELECT f.id FROM isilon_folders f
        INNER JOIN descendants d ON f.parent_folder_id = d.id
        WHERE f.volume_id = #{volume_id}
      )
      SELECT id FROM descendants
    SQL

    ActiveRecord::Base.connection.exec_query(sql).rows.flatten.map(&:to_i).uniq
  end
end
