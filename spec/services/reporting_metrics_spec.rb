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
        ["OK to Migrate", 3],
        ["Don't Migrate", 1],
        ["Save Elsewhere", 0],
        ["Migrated", 2],
        ["Migration in Progress", 1],
        ["Needs Review", 2],
        ["Needs Further Investigation", 1]
      ])
    end
  end
end
