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

  describe "volume scoping" do
    it "allows the same isilon_path in different volumes" do
      volume_a = create(:volume, name: "Volume A")
      volume_b = create(:volume, name: "Volume B")
      folder_a = create(:isilon_folder, volume: volume_a, full_path: "/Volume A/alpha")
      folder_b = create(:isilon_folder, volume: volume_b, full_path: "/Volume B/alpha")

      create(:isilon_asset, parent_folder: folder_a, isilon_name: "file.txt", isilon_path: "/alpha/file.txt")

      expect {
        create(:isilon_asset, parent_folder: folder_b, isilon_name: "file.txt", isilon_path: "/alpha/file.txt")
      }.not_to raise_error

      expect(IsilonAsset.where(isilon_path: "/alpha/file.txt").count).to eq(2)
    end

    it "sets volume from the parent folder when missing" do
      volume = create(:volume, name: "Volume A")
      folder = create(:isilon_folder, volume: volume, full_path: "/Volume A/alpha")
      asset = create(:isilon_asset,
        parent_folder: folder,
        volume: nil,
        isilon_name: "file.txt",
        isilon_path: "/alpha/file.txt")

      expect(asset.volume).to eq(volume)
    end
  end

  describe "descendant_assets_count" do
    let!(:root) { create(:isilon_folder) }
    let!(:child) { create(:isilon_folder, parent_folder: root) }

    it "increments counts up the tree when asset is created" do
      expect {
        create(:isilon_asset, parent_folder: child)
      }.to change { child.reload.descendant_assets_count }.by(1)
      .and change { root.reload.descendant_assets_count }.by(1)
    end

    it "decrements counts when asset is destroyed" do
      asset = create(:isilon_asset, parent_folder: child)

      expect {
        asset.destroy
      }.to change { child.reload.descendant_assets_count }.by(-1)
      .and change { root.reload.descendant_assets_count }.by(-1)
    end
  end
end
