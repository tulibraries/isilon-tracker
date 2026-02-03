# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsilonAsset, type: :model do
  describe "#full_path_with_volume" do
    it "prepends the volume name when available" do
      volume = create(:volume, name: "Deposit")
      folder = create(:isilon_folder, volume: volume, full_path: "/Deposit/alpha")
      asset = create(:isilon_asset, parent_folder: folder, isilon_path: "/alpha/file.txt")

      expect(asset.full_path_with_volume).to eq("/Deposit/alpha/file.txt")
    end

    it "returns isilon_path when volume is missing" do
      volume = create(:volume, name: "Test Volume")
      folder = create(:isilon_folder, volume: volume, full_path: "/alpha")
      asset = create(:isilon_asset, parent_folder: folder, isilon_path: "/alpha/file.txt")

      allow(folder).to receive(:volume).and_return(nil)

      expect(asset.full_path_with_volume).to eq("/alpha/file.txt")
    end
  end

  describe "#duplicates" do
    it "returns all assets in the same duplicate group" do
      asset = create(:isilon_asset, file_checksum: "abc", file_size: "100")
      other = create(:isilon_asset, file_checksum: "abc", file_size: "100")
      group = DuplicateGroup.create!(checksum: "abc")

      DuplicateGroupMembership.create!(duplicate_group: group, isilon_asset: asset)
      DuplicateGroupMembership.create!(duplicate_group: group, isilon_asset: other)

      expect(asset.duplicates).to include(asset, other)
      expect(other.duplicates).to include(asset, other)
    end
  end
end
