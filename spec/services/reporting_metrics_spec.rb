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
end
