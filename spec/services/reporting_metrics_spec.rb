require "rails_helper"

RSpec.describe ReportingMetrics do
  describe ".decision_progress_at_a_glance" do
    before { Rails.cache.clear }

    it "summarizes assets into decision made vs pending buckets with percentages" do
      folder = create(:isilon_folder)

      decision_made_statuses = [
        create(:migration_status, name: "OK to migrate"),
        create(:migration_status, name: "Don’t migrate"), # curly apostrophe
        create(:migration_status, name: "Migrated")
      ]

      pending_statuses = [
        create(:migration_status, name: "Needs review"),
        create(:migration_status, name: "Needs further investigation")
      ]

      3.times do |index|
        create(:isilon_asset, parent_folder: folder, migration_status: decision_made_statuses[index])
      end

      2.times do |index|
        create(:isilon_asset, parent_folder: folder, migration_status: pending_statuses[index])
      end

      result = described_class.decision_progress_at_a_glance

      expect(result[:total]).to eq(5)
      expect(result[:decision_made]).to eq(
        label: "Decision Made",
        count: 3,
        percentage: 60.0
      )
      expect(result[:decision_pending]).to eq(
        label: "Decision Pending",
        count: 2,
        percentage: 40.0
      )
    end
  end

  describe ".migration_status_overview" do
    before { Rails.cache.clear }

    it "returns migration status counts in display order with zeros for missing statuses" do
      folder = create(:isilon_folder)

      ok_to_migrate = create(:migration_status, name: "OK to migrate")
      dont_migrate = create(:migration_status, name: "Don’t migrate")
      save_elsewhere = create(:migration_status, name: "Save elsewhere")
      migrated = create(:migration_status, name: "Migrated")
      in_progress = create(:migration_status, name: "Migration in progress")
      needs_review = create(:migration_status, name: "Needs review")
      needs_further = create(:migration_status, name: "Needs further investigation")

      create_list(:isilon_asset, 3, parent_folder: folder, migration_status: ok_to_migrate)
      create(:isilon_asset, parent_folder: folder, migration_status: dont_migrate)
      create_list(:isilon_asset, 2, parent_folder: folder, migration_status: migrated)
      create(:isilon_asset, parent_folder: folder, migration_status: in_progress)
      create_list(:isilon_asset, 2, parent_folder: folder, migration_status: needs_review)
      create(:isilon_asset, parent_folder: folder, migration_status: needs_further)
      # Explicitly create no assets for Save elsewhere to confirm zero handling
      expect(IsilonAsset.where(migration_status: save_elsewhere)).to be_empty

      result = described_class.migration_status_overview

      expect(result).to eq([
        [ "OK to Migrate", 3 ],
        [ "Don't Migrate", 1 ],
        [ "Save Elsewhere", 0 ],
        [ "Migrated", 2 ],
        [ "Migration in Progress", 1 ],
        [ "Needs Review", 2 ],
        [ "Needs Further Investigation", 1 ]
      ])
    end
  end

  describe ".decision_progress_by_volume" do
    before { Rails.cache.clear }

    it "returns percentage of decision made assets per volume sorted descending" do
      decision_status = create(:migration_status, name: "OK to migrate")
      pending_status = create(:migration_status, name: "Needs review")

      volume_a = create(:volume, name: "Volume A")
      volume_b = create(:volume, name: "Volume B")

      folder_a = create(:isilon_folder, volume: volume_a)
      folder_b = create(:isilon_folder, volume: volume_b)

      create_list(:isilon_asset, 3, parent_folder: folder_a, migration_status: decision_status)
      create(:isilon_asset, parent_folder: folder_a, migration_status: pending_status)

      create(:isilon_asset, parent_folder: folder_b, migration_status: decision_status)
      create_list(:isilon_asset, 3, parent_folder: folder_b, migration_status: pending_status)

      result = described_class.decision_progress_by_volume

      expect(result).to eq([
        [ "Volume A", 75.0 ],
        [ "Volume B", 25.0 ]
      ])
    end
  end

  describe ".decision_progress_by_assigned_user" do
    before { Rails.cache.clear }

    it "returns stacked data sets of decision made vs pending counts per user ordered by workload" do
      decision_status = create(:migration_status, name: "OK to migrate")
      pending_status = create(:migration_status, name: "Needs review")

      user_a = create(:user, name: "User A")
      user_b = create(:user, name: "User B")

      folder = create(:isilon_folder)

      create_list(:isilon_asset, 2, parent_folder: folder, migration_status: decision_status, assigned_to: user_a)
      create(:isilon_asset, parent_folder: folder, migration_status: pending_status, assigned_to: user_a)

      create(:isilon_asset, parent_folder: folder, migration_status: decision_status, assigned_to: user_b)
      create(:isilon_asset, parent_folder: folder, migration_status: pending_status, assigned_to: user_b)

      create(:isilon_asset, parent_folder: folder, migration_status: pending_status, assigned_to: nil)

      result = described_class.decision_progress_by_assigned_user

      expect(result).to eq([
        {
          name: "Decision Made",
          data: {
            "User A" => 2,
            "User B" => 1,
            "Unassigned" => 0
          }
        },
        {
          name: "Decision Pending",
          data: {
            "User A" => 1,
            "User B" => 1,
            "Unassigned" => 1
          }
        }
      ])
    end
  end

  describe ".asset_counts_by_volume_and_migration_status" do
    before { Rails.cache.clear }

    it "returns counts grouped by volume and migration status" do
      volume_a = create(:volume, name: "Volume A")
      volume_b = create(:volume, name: "Volume B")
      status_ok = create(:migration_status, name: "OK to migrate")
      status_review = create(:migration_status, name: "Needs review")
      folder_a = create(:isilon_folder, volume: volume_a)
      folder_b = create(:isilon_folder, volume: volume_b)

      create_list(:isilon_asset, 2, parent_folder: folder_a, migration_status: status_ok)
      create(:isilon_asset, parent_folder: folder_a, migration_status: status_review)

      create(:isilon_asset, parent_folder: folder_b, migration_status: nil)

      result = described_class.asset_counts_by_volume_and_migration_status

      expect(result).to include(
        { volume: "Volume A", migration_status: "Needs review", count: 1 },
        { volume: "Volume A", migration_status: "OK to migrate", count: 2 },
        { volume: "Volume B", migration_status: "Unassigned", count: 1 }
      )
    end
  end

  describe ".asset_counts_by_assigned_user_and_migration_status" do
    before { Rails.cache.clear }

    it "returns counts grouped by assigned user and migration status" do
      user_a = create(:user, name: "User A")
      user_b = create(:user, name: "User B")
      status_ok = create(:migration_status, name: "OK to migrate")
      status_review = create(:migration_status, name: "Needs review")
      folder = create(:isilon_folder)

      create(:isilon_asset, parent_folder: folder, migration_status: status_ok, assigned_to: user_a)
      create(:isilon_asset, parent_folder: folder, migration_status: status_review, assigned_to: user_a)

      create(:isilon_asset, parent_folder: folder, migration_status: nil, assigned_to: user_b)

      result = described_class.asset_counts_by_assigned_user_and_migration_status

      expect(result).to include(
        { assigned_user: "User A", migration_status: "Needs review", count: 1 },
        { assigned_user: "User A", migration_status: "OK to migrate", count: 1 },
        { assigned_user: "User B", migration_status: "Unassigned", count: 1 }
      )
    end
  end
end
