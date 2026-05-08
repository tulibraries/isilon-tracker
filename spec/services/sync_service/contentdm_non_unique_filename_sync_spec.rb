# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncService::ContentdmNonUniqueFilenameSync, type: :service do
  around do |example|
    FileUtils.rm_f(described_class::NON_MATCHES_CSV_PATH)
    example.run
    FileUtils.rm_f(described_class::NON_MATCHES_CSV_PATH)
  end

  FIXTURE_FILE = Rails.root.join(
    "spec/fixtures/files/contentdm_non_unique_filename_sync/scrc_manuscripts_non-unique_filenames.csv"
  )

  let!(:scrc_collection) { FactoryBot.create(:contentdm_collection, name: "SCRC Manuscripts") }
  let!(:volume_one) { FactoryBot.create(:volume, name: "Volume One") }
  let!(:volume_two) { FactoryBot.create(:volume, name: "Volume Two") }
  let!(:matching_folder_one) do
    FactoryBot.create(:isilon_folder, volume: volume_one, full_path: "/collections/AMANU_201104000002")
  end
  let!(:matching_folder_two) do
    FactoryBot.create(:isilon_folder, volume: volume_two, full_path: "/archives/boxes/AMANU_201104000002")
  end
  let!(:other_folder) do
    FactoryBot.create(:isilon_folder, volume: volume_one, full_path: "/collections/AMANU_201104000003")
  end

  let!(:asset_one) do
    FactoryBot.create(
      :isilon_asset,
      parent_folder: matching_folder_one,
      isilon_name: "001_Page 1.tif"
    )
  end
  let!(:asset_two) do
    FactoryBot.create(
      :isilon_asset,
      parent_folder: matching_folder_two,
      isilon_name: "001_Page 1.tif",
      notes: "Needs review"
    )
  end
  let!(:other_asset) do
    FactoryBot.create(
      :isilon_asset,
      parent_folder: other_folder,
      isilon_name: "001_Page 1.tif"
    )
  end

  describe "#sync" do
    it "matches by parent folder basename plus filename and updates all matching assets" do
      result = described_class.call(file_path: FIXTURE_FILE)

      expect(result.updated_count).to eq(2)
      expect(result.rows_touched).to eq(2)
      expect(result.rows_matched).to eq(1)
      expect(result.rows_unmatched).to eq(1)
      expect(result.rows_discarded).to eq(0)

      expect(asset_one.reload.contentdm_collection).to eq(scrc_collection)
      expect(asset_one.reload.notes).to eq(described_class::CONTENTDM_FILENAME_MATCH_NOTE)

      expect(asset_two.reload.contentdm_collection).to eq(scrc_collection)
      expect(asset_two.reload.notes).to eq(
        "Needs review; #{described_class::CONTENTDM_FILENAME_MATCH_NOTE}"
      )

      expect(other_asset.reload.contentdm_collection).to be_nil
    end

    it "writes unmatched rows to a csv in tmp" do
      described_class.call(file_path: FIXTURE_FILE)

      rows = CSV.read(described_class::NON_MATCHES_CSV_PATH)
      expect(rows).to eq([
        [ "File Name", "Collection" ],
        [ "AMANU_201104000999/001_Page 1.tif", "SCRC Manuscripts" ]
      ])
    end

    it "rejects when the csv file is missing" do
      expect {
        described_class.call(file_path: "missing.csv")
      }.to raise_error(ArgumentError, /CSV file not found/)
    end
  end
end
