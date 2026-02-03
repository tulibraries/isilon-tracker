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
    let!(:deposit_volume) { create(:volume, name: "Deposit") }
    let!(:media_volume) { create(:volume, name: "Media-Repository") }
    let!(:deposit_folder) { create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project") }
    let!(:media_folder) { create(:isilon_folder, volume: media_volume, full_path: "/Media-Repository/project") }

    it "groups assets with matching checksums" do
      original = create(:isilon_asset, parent_folder: deposit_folder, file_checksum: "abc", file_size: "100")
      create(:isilon_asset, parent_folder: deposit_folder, file_checksum: "abc", file_size: "100")
      create(:isilon_asset, parent_folder: media_folder, file_checksum: "abc", file_size: "100")
      create(:isilon_asset, parent_folder: media_folder, file_checksum: "def", file_size: "100")
      create(:isilon_asset, parent_folder: media_folder, file_checksum: "abc", file_size: "0")
      create(:isilon_asset, parent_folder: media_folder, file_checksum: "", file_size: "100")

      Rake::Task["duplicates:detect"].invoke

      group = DuplicateGroup.find_by(checksum: "abc")
      expect(group).to be_present
      expect(group.isilon_assets.count).to eq(4)
      expect(group.isilon_assets).to include(original)

      expect(IsilonAsset.where(has_duplicates: true).count).to eq(4)
      expect(IsilonAsset.where(has_duplicates: false).count).to eq(2)
    end
  end

  describe "duplicates:clear" do
    it "clears duplicate groups and resets has_duplicates" do
      asset = create(:isilon_asset, file_checksum: "abc", file_size: "100", has_duplicates: true)
      group = DuplicateGroup.create!(checksum: "abc")
      DuplicateGroupMembership.create!(duplicate_group: group, isilon_asset: asset)

      allow(STDIN).to receive(:gets).and_return("yes\n")

      Rake::Task["duplicates:clear"].invoke

      expect(DuplicateGroup.count).to eq(0)
      expect(DuplicateGroupMembership.count).to eq(0)
      expect(asset.reload.has_duplicates).to be(false)
    end
  end
end
