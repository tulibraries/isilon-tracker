# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Volumes batch actions", type: :request do
  let!(:volume) { FactoryBot.create(:volume) }
  let!(:user) { FactoryBot.create(:user, email: "tester@temple.edu") }
  let!(:other_user) { FactoryBot.create(:user, email: "other@temple.edu", name: "Other User") }

  let!(:migration_status_1) { FactoryBot.create(:migration_status, name: "Needs Review") }
  let!(:migration_status_2) { FactoryBot.create(:migration_status, name: "In Progress") }
  let!(:migration_status_3) { FactoryBot.create(:migration_status, name: "Migrated") }

  let!(:aspace_collection_1) { FactoryBot.create(:aspace_collection, name: "Collection A") }
  let!(:aspace_collection_2) { FactoryBot.create(:aspace_collection, name: "Collection B") }

  let!(:parent_folder) { FactoryBot.create(:isilon_folder, volume: volume, parent_folder: nil, full_path: "/test") }

  let!(:child_folder_1) do
    FactoryBot.create(:isilon_folder,
      volume: volume,
      parent_folder: parent_folder,
      full_path: "/test/subfolder1",
      assigned_to: nil)
  end

  let!(:child_folder_2) do
    FactoryBot.create(:isilon_folder,
      volume: volume,
      parent_folder: parent_folder,
      full_path: "/test/subfolder2",
      assigned_to: nil)
  end

  let!(:asset_1) do
    FactoryBot.create(:isilon_asset,
      parent_folder: parent_folder,
      isilon_name: "asset1.txt",
      migration_status: migration_status_1,
      assigned_to: nil,
      aspace_collection: nil,
      aspace_linking_status: "false")
  end

  let!(:asset_2) do
    FactoryBot.create(:isilon_asset,
      parent_folder: parent_folder,
      isilon_name: "asset2.txt",
      migration_status: migration_status_1,
      assigned_to: nil,
      aspace_collection: nil,
      aspace_linking_status: "false")
  end

  let!(:asset_3) do
    FactoryBot.create(:isilon_asset,
      parent_folder: parent_folder,
      isilon_name: "asset3.txt",
      migration_status: migration_status_2,
      assigned_to: user,
      aspace_collection: aspace_collection_1,
      aspace_linking_status: "true")
  end

  # Assets within child folders for cascading tests
  let!(:nested_asset_1) do
    FactoryBot.create(:isilon_asset,
      parent_folder: child_folder_1,
      isilon_name: "nested1.txt",
      migration_status: migration_status_1,
      assigned_to: nil)
  end

  let!(:nested_asset_2) do
    FactoryBot.create(:isilon_asset,
      parent_folder: child_folder_2,
      isilon_name: "nested2.txt",
      migration_status: migration_status_1,
      assigned_to: nil)
  end

  before { sign_in user }

  describe "PATCH #update" do
    context "when updating migration status" do
      it "updates migration status for selected assets" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload
        asset_3.reload

        expect(asset_1.migration_status).to eq(migration_status_2)
        expect(asset_2.migration_status).to eq(migration_status_2)
        expect(asset_3.migration_status).to eq(migration_status_2) # unchanged

        expect(flash[:notice]).to include("migration status to In Progress")
      end
    end

    context "when updating assigned user" do
      it "updates assigned user for selected assets" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          assigned_user_id: other_user.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload
        asset_3.reload

        expect(asset_1.assigned_to).to eq(other_user)
        expect(asset_2.assigned_to).to eq(other_user)
        expect(asset_3.assigned_to).to eq(user) # unchanged

        expect(flash[:notice]).to include("assigned user to Other User")
      end
    end

    context "when updating ASpace collection" do
      it "updates ASpace collection for selected assets" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          aspace_collection_id: aspace_collection_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload
        asset_3.reload

        expect(asset_1.aspace_collection).to eq(aspace_collection_2)
        expect(asset_2.aspace_collection).to eq(aspace_collection_2)
        expect(asset_3.aspace_collection).to eq(aspace_collection_1) # unchanged

        expect(flash[:notice]).to include("ASpace collection to Collection B")
      end

      it "clears ASpace collection for selected assets" do
        asset_1.update!(aspace_collection: aspace_collection_2)
        asset_2.update!(aspace_collection: aspace_collection_2)

        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          aspace_collection_id: "none"
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload
        asset_3.reload

        expect(asset_1.aspace_collection).to be_nil
        expect(asset_2.aspace_collection).to be_nil
        expect(asset_3.aspace_collection).to eq(aspace_collection_1)

        expect(flash[:notice]).to include("ASpace collection cleared")
      end
    end

    context "when updating ASpace linking status" do
      it "updates ASpace linking status to linked for selected assets" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          aspace_linking_status: "true"
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload
        asset_3.reload

        expect(asset_1.aspace_linking_status).to eq("true")
        expect(asset_2.aspace_linking_status).to eq("true")
        expect(asset_3.aspace_linking_status).to eq("true") # unchanged but already true

        expect(flash[:notice]).to include("ASpace linking status to linked")
      end

      it "updates ASpace linking status to not linked for selected assets" do
        # First set asset_1 and asset_2 to linked
        asset_1.update!(aspace_linking_status: "true")
        asset_2.update!(aspace_linking_status: "true")

        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          aspace_linking_status: "false"
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload
        asset_3.reload

        expect(asset_1.aspace_linking_status).to eq("false")
        expect(asset_2.aspace_linking_status).to eq("false")
        expect(asset_3.aspace_linking_status).to eq("true") # unchanged

        expect(flash[:notice]).to include("ASpace linking status to not linked")
      end
    end

    context "when updating notes" do
      it "appends notes with a semicolon delimiter" do
        asset_1.update!(notes: "First note")
        asset_2.update!(notes: nil)

        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          notes_action: "append",
          notes: "Second note"
        }

        expect(response).to have_http_status(:redirect)

        asset_1.reload
        asset_2.reload

        expect(asset_1.notes).to eq("First note; Second note")
        expect(asset_2.notes).to eq("Second note")
        expect(flash[:notice]).to include("notes appended")
      end

      it "replaces notes even when the new value is blank" do
        asset_1.update!(notes: "Existing note")

        patch volume_batch_actions_path(volume), params: {
          asset_ids: asset_1.id.to_s,
          notes_action: "replace",
          notes: ""
        }

        expect(response).to have_http_status(:redirect)
        expect(asset_1.reload.notes).to eq("")
        expect(flash[:notice]).to include("notes replaced")
      end

      it "clears notes for selected assets" do
        asset_1.update!(notes: "Existing note")

        patch volume_batch_actions_path(volume), params: {
          asset_ids: asset_1.id.to_s,
          notes_action: "clear",
          notes: "ignored"
        }

        expect(response).to have_http_status(:redirect)
        expect(asset_1.reload.notes).to be_nil
        expect(flash[:notice]).to include("notes cleared")
      end
    end

    context "when updating notes for folders and descendants" do
      it "applies notes to selected folders and assets under those folders" do
        child_folder_1.update!(notes: "Folder note")
        nested_asset_1.update!(notes: "Asset note")
        asset_1.update!(notes: "Root asset")

        patch volume_batch_actions_path(volume), params: {
          folder_ids: "#{child_folder_1.id},#{child_folder_2.id}",
          notes_action: "append",
          notes: "New note"
        }

        expect(response).to have_http_status(:redirect)

        expect(child_folder_1.reload.notes).to eq("Folder note; New note")
        expect(child_folder_2.reload.notes).to eq("New note")
        expect(nested_asset_1.reload.notes).to eq("Asset note; New note")
        expect(nested_asset_2.reload.notes).to eq("New note")
        expect(asset_1.reload.notes).to eq("Root asset")
        expect(flash[:notice]).to include("notes appended")
      end

      it "does not double-append when assets are explicitly selected" do
        nested_asset_1.update!(notes: "Asset note")

        patch volume_batch_actions_path(volume), params: {
          folder_ids: child_folder_1.id.to_s,
          asset_ids: nested_asset_1.id.to_s,
          notes_action: "append",
          notes: "New note"
        }

        expect(response).to have_http_status(:redirect)
        expect(nested_asset_1.reload.notes).to eq("Asset note; New note")
      end

      it "replaces notes for selected folders and descendant assets" do
        child_folder_1.update!(notes: "Folder note")
        nested_asset_1.update!(notes: "Asset note")

        patch volume_batch_actions_path(volume), params: {
          folder_ids: "#{child_folder_1.id},#{child_folder_2.id}",
          notes_action: "replace",
          notes: ""
        }

        expect(response).to have_http_status(:redirect)
        expect(child_folder_1.reload.notes).to eq("")
        expect(child_folder_2.reload.notes).to eq("")
        expect(nested_asset_1.reload.notes).to eq("")
        expect(nested_asset_2.reload.notes).to eq("")
        expect(flash[:notice]).to include("notes replaced")
      end

      it "clears notes for selected folders and descendant assets" do
        child_folder_1.update!(notes: "Folder note")
        nested_asset_1.update!(notes: "Asset note")

        patch volume_batch_actions_path(volume), params: {
          folder_ids: "#{child_folder_1.id},#{child_folder_2.id}",
          notes_action: "clear",
          notes: "ignored"
        }

        expect(response).to have_http_status(:redirect)
        expect(child_folder_1.reload.notes).to be_nil
        expect(child_folder_2.reload.notes).to be_nil
        expect(nested_asset_1.reload.notes).to be_nil
        expect(nested_asset_2.reload.notes).to be_nil
        expect(flash[:notice]).to include("notes cleared")
      end
    end

    context "when updating multiple fields simultaneously" do
      it "updates all specified fields for selected assets" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          migration_status_id: migration_status_3.id,
          assigned_user_id: other_user.id,
          aspace_collection_id: aspace_collection_2.id,
          aspace_linking_status: "true"
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload

        # Check all fields were updated
        expect(asset_1.migration_status).to eq(migration_status_3)
        expect(asset_1.assigned_to).to eq(other_user)
        expect(asset_1.aspace_collection).to eq(aspace_collection_2)
        expect(asset_1.aspace_linking_status).to eq("true")

        expect(asset_2.migration_status).to eq(migration_status_3)
        expect(asset_2.assigned_to).to eq(other_user)
        expect(asset_2.aspace_collection).to eq(aspace_collection_2)
        expect(asset_2.aspace_linking_status).to eq("true")

        # Check flash message includes all updates
        notice = flash[:notice]
        expect(notice).to include("migration status to Migrated")
        expect(notice).to include("assigned user to Other User")
        expect(notice).to include("ASpace collection to Collection B")
        expect(notice).to include("ASpace linking status to linked")
      end
    end

    context "when no changes are specified (all unchanged)" do
      it "redirects with no changes message" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}"
          # No other parameters - all fields left as "Unchanged"
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))
        expect(flash[:notice]).to eq("Batch update completed successfully. No changes were made.")
      end
    end

    context "when updating folders only" do
      it "updates assigned user for selected folders without cascading" do
        patch volume_batch_actions_path(volume), params: {
          folder_ids: "#{child_folder_1.id},#{child_folder_2.id}",
          assigned_user_id: other_user.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        child_folder_1.reload
        child_folder_2.reload
        nested_asset_1.reload
        nested_asset_2.reload

        # Folders should be updated
        expect(child_folder_1.assigned_to).to eq(other_user)
        expect(child_folder_2.assigned_to).to eq(other_user)

        # Assets within folders should NOT be updated (no cascading)
        expect(nested_asset_1.assigned_to).to be_nil
        expect(nested_asset_2.assigned_to).to be_nil

        expect(flash[:notice]).to include("assigned folders to Other User")
      end
    end



    context "with invalid folder IDs" do
      it "handles empty folder_ids" do
        patch volume_batch_actions_path(volume), params: {
          folder_ids: "",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))
        expect(flash[:alert]).to eq("No assets or folders selected for batch update.")
      end

      it "handles non-existent folder IDs" do
        patch volume_batch_actions_path(volume), params: {
          folder_ids: "99999,88888",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))
        expect(flash[:alert]).to eq("No valid assets or folders found for batch update.")
      end
    end

    context "with invalid asset IDs" do
      it "handles empty asset_ids" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))
        expect(flash[:alert]).to eq("No assets or folders selected for batch update.")
      end

      it "handles non-existent asset IDs" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "99999,88888",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))
        expect(flash[:alert]).to eq("No valid assets or folders found for batch update.")
      end

      it "filters out invalid asset IDs but processes valid ones" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},99999,#{asset_2.id}",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))

        asset_1.reload
        asset_2.reload

        expect(asset_1.migration_status).to eq(migration_status_2)
        expect(asset_2.migration_status).to eq(migration_status_2)
        expect(flash[:notice]).to include("migration status to In Progress")
      end
    end

    context "when using Turbo Stream requests" do
      it "responds with turbo stream for AJAX requests" do
        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id}",
          migration_status_id: migration_status_2.id
        }, headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('text/vnd.turbo-stream.html')
      end
    end

    context "with transaction rollback on error" do
      it "rolls back all changes if an error occurs during update" do
        original_status_1 = asset_1.migration_status
        original_status_2 = asset_2.migration_status

        # Mock MigrationStatus.find to raise an error - params come as strings
        allow(MigrationStatus).to receive(:find).with(migration_status_2.id.to_s).and_raise(StandardError, "Database error")

        patch volume_batch_actions_path(volume), params: {
          asset_ids: "#{asset_1.id},#{asset_2.id}",
          migration_status_id: migration_status_2.id
        }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(volume_path(volume))
        expect(flash[:alert]).to include("An error occurred")

        asset_1.reload
        asset_2.reload

        # Assets should remain unchanged due to rollback
        expect(asset_1.migration_status).to eq(original_status_1)
        expect(asset_2.migration_status).to eq(original_status_2)
      end
    end
  end
end
