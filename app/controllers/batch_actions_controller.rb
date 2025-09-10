class BatchActionsController < ApplicationController
  before_action :set_volume

  def update
    asset_ids = params[:asset_ids].to_s.split(",").map(&:to_i).reject(&:zero?)
    folder_ids = params[:folder_ids].to_s.split(",").map(&:to_i).reject(&:zero?)

    if asset_ids.empty? && folder_ids.empty?
      redirect_to @volume, alert: "No assets or folders selected for batch update."
      return
    end

    # Determine which form was submitted based on commit button text
    is_assign_form = params[:commit] == "Assign"

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
            # Only cascade to child assets for assign form, not folder form
            cascade_to_assets = is_assign_form
            updated_count += process_folder_updates(folders, updates_applied, cascade_to_assets)
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

    assets.count
  end

  def process_folder_updates(folders, updates_applied, cascade_to_assets = false)
    updated_count = 0

    folders.each do |folder|
      folder_updates = 0

      # Update the folder itself and cascade to subfolders and assets
      # Only assigned_to is supported for folders currently
      if params[:assigned_user_id].present?
        user = nil
        if params[:assigned_user_id] != "unassigned"
          user = User.find(params[:assigned_user_id])
        end

        # Update the folder
        folder.update!(assigned_to: user)
        folder_updates += 1

        # Update all descendant folders
        descendant_folders = folder.descendant_folders
        descendant_folders.each do |subfolder|
          subfolder.update!(assigned_to: user)
          folder_updates += 1
        end

        # Only update assets if cascading is enabled (assign form)
        if cascade_to_assets
          # Update all assets in this folder and subfolders
          all_assets = folder.all_descendant_assets
          if all_assets.any?
            all_assets.update_all(assigned_to: user&.id)
            folder_updates += all_assets.count
          end
        end

        if cascade_to_assets
          updates_applied << "assigned user to #{user ? user.display_name : 'unassigned'} (cascaded from folder: #{folder.full_path})"
        else
          updates_applied << "assigned user to #{user ? user.display_name : 'unassigned'} for folder: #{folder.full_path} (folders only)"
        end
      end

      updated_count += folder_updates
    end

    updated_count
  end
end
