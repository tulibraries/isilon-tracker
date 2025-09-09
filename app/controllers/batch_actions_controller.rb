class BatchActionsController < ApplicationController
  before_action :set_volume

  def update
    asset_ids = params[:asset_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if asset_ids.empty?
      redirect_to @volume, alert: "No assets selected for batch update."
      return
    end

    assets = @volume.isilon_assets.where(id: asset_ids)

    if assets.empty?
      redirect_to @volume, alert: "No valid assets found for batch update."
      return
    end

    updated_count = 0
    updates_applied = []

    begin
      # Process each field that might have been changed
      assets.transaction do
        # Update Migration Status
        if params[:migration_status_id].present?
          migration_status = MigrationStatus.find(params[:migration_status_id])
          assets.update_all(migration_status_id: migration_status.id)
          updates_applied << "migration status to #{migration_status.name}"
        end

        # Update Assigned User
        if params[:assigned_user_id].present?
          if params[:assigned_user_id] == "unassigned"
            assets.update_all(assigned_to: nil)
            updates_applied << "assigned user to unassigned"
          else
            user = User.find(params[:assigned_user_id])
            assets.update_all(assigned_to: user.id)
            updates_applied << "assigned user to #{user.display_name}"
          end
        end

        # Update ASpace Collection
        if params[:aspace_collection_id].present?
          aspace_collection = AspaceCollection.find(params[:aspace_collection_id])
          assets.update_all(aspace_collection_id: aspace_collection.id)
          updates_applied << "ASpace collection to #{aspace_collection.name}"
        end

        # Update ASpace Linking Status
        if params[:aspace_linking_status].present? && params[:aspace_linking_status] != ""
          linking_status = params[:aspace_linking_status]
          assets.update_all(aspace_linking_status: linking_status)
          status_text = linking_status == "true" ? "linked" : "not linked"
          updates_applied << "ASpace linking status to #{status_text}"
        end

        updated_count = assets.count
      end
    rescue StandardError => e
      error_message = "An error occurred while updating assets: #{e.message}"

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
      success_message = "Successfully updated #{updated_count} asset#{'s' if updated_count != 1}: #{updates_applied.join(', ')}"

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
end
