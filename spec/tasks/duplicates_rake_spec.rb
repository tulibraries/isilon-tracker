# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "duplicates rake tasks", type: :task do
  before(:all) do
    Rake.application.rake_require "tasks/detect_duplicates"
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task["duplicates:detect"].reenable if Rake::Task.task_defined?("duplicates:detect")
  end

  describe "duplicates:detect" do
    let!(:dont_migrate_status) { create(:migration_status, :dont_migrate) }
    let!(:deposit_volume) { create(:volume, name: "Deposit") }
    let!(:media_volume) { create(:volume, name: "Media-Repository") }
    let!(:other_volume) { create(:volume, name: "Other") }
    let!(:deposit_folder) { create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project") }
    let!(:media_folder) { create(:isilon_folder, volume: media_volume, full_path: "/Media-Repository/project") }
    let!(:other_folder) { create(:isilon_folder, volume: other_volume, full_path: "/Other/project") }

    it "marks outside assets as duplicates of originals in main volumes" do
      original = create(:isilon_asset, parent_folder: deposit_folder, file_checksum: "abc", file_size: "100")
      create(:isilon_asset, parent_folder: deposit_folder, file_checksum: "abc", file_size: "100")
      outside_dup = create(:isilon_asset, parent_folder: other_folder, file_checksum: "abc", file_size: "100")
      outside_no_match = create(:isilon_asset, parent_folder: other_folder, file_checksum: "def", file_size: "100")
      outside_zero_size = create(:isilon_asset, parent_folder: other_folder, file_checksum: "abc", file_size: "0")
      main_asset = create(:isilon_asset, parent_folder: media_folder, file_checksum: "xyz", file_size: "100")

      Rake::Task["duplicates:detect"].invoke

      expect(outside_dup.reload.duplicate_of_id).to eq(original.id)
      expect(outside_dup.migration_status_id).to eq(dont_migrate_status.id)
      expect(outside_no_match.reload.duplicate_of_id).to be_nil
      expect(outside_zero_size.reload.duplicate_of_id).to be_nil
      expect(main_asset.reload.duplicate_of_id).to be_nil
    end
  end
end
