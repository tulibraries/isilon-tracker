# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncService::BulkUpdate, type: :service do
  let!(:volume) { create(:volume, name: "Deposit") }
  let!(:other_volume) { create(:volume, name: "Media-Repository") }

  let!(:root_folder) do
    create(:isilon_folder, volume: volume, full_path: "/collections/root")
  end
  let!(:child_folder) do
    create(:isilon_folder, volume: volume, parent_folder: root_folder, full_path: "/collections/root/child")
  end
  let!(:grandchild_folder) do
    create(:isilon_folder, volume: volume, parent_folder: child_folder, full_path: "/collections/root/child/grandchild")
  end
  let!(:sibling_folder) do
    create(:isilon_folder, volume: volume, full_path: "/collections/sibling")
  end
  let!(:same_path_other_volume) do
    create(:isilon_folder, volume: other_volume, full_path: "/collections/root")
  end

  let!(:status_one) { create(:migration_status, name: "Needs Review") }
  let!(:status_two) { create(:migration_status, name: "Migrated") }
  let!(:user_one) { create(:user, name: "User One") }
  let!(:user_two) { create(:user, name: "User Two") }

  let!(:root_asset) do
    create(:isilon_asset, parent_folder: root_folder, migration_status: status_one, assigned_to: user_one)
  end
  let!(:child_asset) do
    create(:isilon_asset, parent_folder: child_folder, migration_status: status_one, assigned_to: nil)
  end
  let!(:grandchild_asset) do
    create(:isilon_asset, parent_folder: grandchild_folder, migration_status: status_one, assigned_to: nil)
  end
  let!(:sibling_asset) do
    create(:isilon_asset, parent_folder: sibling_folder, migration_status: status_one, assigned_to: user_one)
  end
  let!(:other_volume_asset) do
    create(:isilon_asset, parent_folder: same_path_other_volume, migration_status: status_one, assigned_to: user_one)
  end

  describe ".call" do
    it "updates assets in the selected folder and all descendant folders" do
      result = described_class.call(
        volume_id: volume.id,
        full_path: root_folder.full_path,
        updates: {
          migration_status_id: status_two.id,
          assigned_to_id: user_two.id
        }
      )

      expect(result.updated_count).to eq(6)
      expect(result.asset_updated_count).to eq(3)
      expect(result.folder_updated_count).to eq(3)
      expect(result.folder_count).to eq(3)
      expect(result.volume_id).to eq(volume.id)
      expect(result.full_path).to eq(root_folder.full_path)

      expect(root_asset.reload.migration_status).to eq(status_two)
      expect(child_asset.reload.migration_status).to eq(status_two)
      expect(grandchild_asset.reload.migration_status).to eq(status_two)

      expect(root_asset.reload.assigned_to).to eq(user_two)
      expect(child_asset.reload.assigned_to).to eq(user_two)
      expect(grandchild_asset.reload.assigned_to).to eq(user_two)
      expect(root_folder.reload.assigned_to).to eq(user_two)
      expect(child_folder.reload.assigned_to).to eq(user_two)
      expect(grandchild_folder.reload.assigned_to).to eq(user_two)

      expect(sibling_asset.reload.migration_status).to eq(status_one)
      expect(other_volume_asset.reload.migration_status).to eq(status_one)
      expect(sibling_folder.reload.assigned_to).to be_nil
      expect(same_path_other_volume.reload.assigned_to).to be_nil
    end

    it "updates only the requested field when one field is omitted" do
      result = described_class.call(
        volume_id: volume.id,
        full_path: root_folder.full_path,
        updates: {
          assigned_to_id: user_two.id
        }
      )

      expect(result.updated_count).to eq(6)
      expect(result.asset_updated_count).to eq(3)
      expect(result.folder_updated_count).to eq(3)
      expect(root_asset.reload.assigned_to).to eq(user_two)
      expect(child_asset.reload.assigned_to).to eq(user_two)
      expect(grandchild_asset.reload.assigned_to).to eq(user_two)
      expect(root_folder.reload.assigned_to).to eq(user_two)
      expect(child_folder.reload.assigned_to).to eq(user_two)
      expect(grandchild_folder.reload.assigned_to).to eq(user_two)

      expect(root_asset.reload.migration_status).to eq(status_one)
      expect(child_asset.reload.migration_status).to eq(status_one)
      expect(grandchild_asset.reload.migration_status).to eq(status_one)
    end

    it "supports clearing assigned user across descendant assets" do
      child_asset.update!(assigned_to: user_one)
      grandchild_asset.update!(assigned_to: user_one)

      result = described_class.call(
        volume_id: volume.id,
        full_path: root_folder.full_path,
        updates: {
          assigned_to_id: nil
        }
      )

      expect(result.updated_count).to eq(6)
      expect(result.asset_updated_count).to eq(3)
      expect(result.folder_updated_count).to eq(3)
      expect(root_asset.reload.assigned_to).to be_nil
      expect(child_asset.reload.assigned_to).to be_nil
      expect(grandchild_asset.reload.assigned_to).to be_nil
      expect(root_folder.reload.assigned_to).to be_nil
      expect(child_folder.reload.assigned_to).to be_nil
      expect(grandchild_folder.reload.assigned_to).to be_nil
    end

    it "does not update folders when only migration status is requested" do
      result = described_class.call(
        volume_id: volume.id,
        full_path: root_folder.full_path,
        updates: {
          migration_status_id: status_two.id
        }
      )

      expect(result.updated_count).to eq(3)
      expect(result.asset_updated_count).to eq(3)
      expect(result.folder_updated_count).to eq(0)
      expect(root_folder.reload.assigned_to).to be_nil
      expect(child_folder.reload.assigned_to).to be_nil
      expect(grandchild_folder.reload.assigned_to).to be_nil
    end

    it "raises when the folder cannot be found within the selected volume" do
      expect {
        described_class.call(
          volume_id: volume.id,
          full_path: "/collections/missing",
          updates: {
            migration_status_id: status_two.id
          }
        )
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises when no update fields are provided" do
      expect {
        described_class.call(
          volume_id: volume.id,
          full_path: root_folder.full_path,
          updates: {}
        )
      }.to raise_error(ArgumentError, /At least one update field is required/)
    end
  end
end
