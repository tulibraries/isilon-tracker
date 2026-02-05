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
    let(:export_path) { Rails.root.join("log/isilon-duplicate-paths.csv") }
    let(:detect_log_path) { Rails.root.join("log/isilon-duplicates-detect.log") }

    after do
      File.delete(export_path) if File.exist?(export_path)
      File.delete(detect_log_path) if File.exist?(detect_log_path)
    end

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

    it "exports child rows with checksum and file size for checksums shared across main and outside volumes" do
      other_volume = create(:volume, name: "Other")
      other_folder = create(:isilon_folder, volume: other_volume, full_path: "/Other/project")

      create(:isilon_asset, parent_folder: deposit_folder, isilon_path: "/project/main.txt", isilon_name: "main.txt", file_checksum: "abc", file_size: "100")
      create(:isilon_asset, parent_folder: media_folder, isilon_path: "/project/main2.txt", isilon_name: "main2.txt", file_checksum: "abc", file_size: "100")
      outside_asset = create(:isilon_asset, parent_folder: other_folder, isilon_path: "/project/out.txt", isilon_name: "out.txt", file_checksum: "abc", file_size: "100")
      create(:isilon_asset, parent_folder: other_folder, isilon_path: "/project/solo.txt", isilon_name: "solo.txt", file_checksum: "xyz", file_size: "100")

      Rake::Task["duplicates:detect"].invoke

      exported = CSV.read(export_path, headers: true)
      child_row = exported.find { |row| row["File"] == "out.txt" }
      solo_row = exported.find { |row| row["File"] == "solo.txt" }

      expect(child_row).to be_present
      expect(child_row["Path"]).to eq("/Other/project/out.txt")
      expect(child_row["Checksum"]).to eq("abc")
      expect(child_row["File Size"]).to eq("100")
      expect(exported.find { |row| row["File"] == "main.txt" }).to be_nil
      expect(exported.find { |row| row["File"] == "main2.txt" }).to be_nil
      expect(solo_row).to be_nil
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
