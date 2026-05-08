# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncService::ContentdmFilenameSync, type: :service do
  around do |example|
    FileUtils.rm_f(described_class::NON_MATCHES_CSV_PATH)
    example.run
    FileUtils.rm_f(described_class::NON_MATCHES_CSV_PATH)
  end

  FIXTURE_FOLDER = Rails.root.join("spec/fixtures/files/contentdm_filename_sync")

  def with_csv_folder(fixture_files)
    Dir.mktmpdir("contentdm-folder") do |dir|
      fixture_files.each do |fixture_name|
        fixture_path = FIXTURE_FOLDER.join(fixture_name)
        FileUtils.cp(fixture_path, File.join(dir, fixture_name))
      end

      yield dir
    end
  end

  let!(:target_asset) do
    FactoryBot.create(:isilon_asset, isilon_name: "match-one.tif", isilon_path: "/alpha/match-one.tif")
  end
  let!(:second_target_asset) do
    FactoryBot.create(
      :isilon_asset,
      isilon_name: "match-two.tif",
      isilon_path: "/alpha/match-two.tif",
      notes: "Needs review"
    )
  end
  let!(:untouched_asset) do
    FactoryBot.create(:isilon_asset, isilon_name: "other-file.tif", isilon_path: "/alpha/other-file.tif")
  end
  let!(:bulletin_asset) do
    FactoryBot.create(:isilon_asset, isilon_name: "b036001m.tif", isilon_path: "/alpha/b036001m.tif")
  end
  let!(:ambler_overlap_asset) do
    FactoryBot.create(:isilon_asset, isilon_name: "00130001.jpg", isilon_path: "/alpha/00130001.jpg")
  end
  let!(:temple_photos_collection) { FactoryBot.create(:contentdm_collection, name: "Temple Photos") }
  let!(:temple_av_collection) { FactoryBot.create(:contentdm_collection, name: "Temple AV") }
  let!(:bulletin_photos_collection) do
    FactoryBot.create(:contentdm_collection, name: "George D. McDowell Philadelphia Evening Bulletin Photographs")
  end
  let!(:bulletin_restricted_collection) do
    FactoryBot.create(:contentdm_collection, name: "Philadelphia Evening Bulletin Photographs - Restricted")
  end
  let!(:ambler_collection) { FactoryBot.create(:contentdm_collection, name: "Ambler Campus History in Photographs") }
  let!(:scrc_photographs_collection) { FactoryBot.create(:contentdm_collection, name: "SCRC Photographs") }

  describe "#sync" do
    it "updates matching assets with both collection and appended note" do
      with_csv_folder(%w[matching_assets.csv]) do |dir|
        result = described_class.call(csv_folder: dir)

        expect(result.updated_count).to eq(2)
        expect(result.rows_touched).to eq(2)
        expect(result.rows_matched).to eq(2)
        expect(result.rows_unmatched).to eq(0)
        expect(result.rows_discarded).to eq(0)
        expect(target_asset.reload.contentdm_collection).to eq(temple_photos_collection)
        expect(target_asset.reload.notes).to eq(described_class::CONTENTDM_FILENAME_MATCH_NOTE)
        expect(second_target_asset.reload.contentdm_collection).to eq(temple_photos_collection)
        expect(second_target_asset.reload.notes).to eq(
          "Needs review; #{described_class::CONTENTDM_FILENAME_MATCH_NOTE}"
        )
        expect(untouched_asset.reload.contentdm_collection).to be_nil
        expect(untouched_asset.reload.notes).to be_nil
      end
    end

    it "does not duplicate the note when run more than once" do
      with_csv_folder(%w[single_match.csv]) do |dir|
        2.times { described_class.call(csv_folder: dir) }

        expect(target_asset.reload.notes).to eq(described_class::CONTENTDM_FILENAME_MATCH_NOTE)
      end
    end

    it "processes all csv files in the configured folder" do
      with_csv_folder(%w[part1.csv part2.csv]) do |dir|
        result = described_class.call(csv_folder: dir)

        expect(result.updated_count).to eq(2)
        expect(result.rows_touched).to eq(2)
        expect(result.rows_matched).to eq(2)
        expect(result.rows_unmatched).to eq(0)
        expect(result.rows_discarded).to eq(0)
        expect(target_asset.reload.contentdm_collection.name).to eq("Temple Photos")
        expect(second_target_asset.reload.contentdm_collection.name).to eq("Temple AV")
      end
    end

    it "ignores the non-unique SCRC filename csv" do
      with_csv_folder(%w[single_match.csv scrc_manuscripts_non-unique_filenames.csv]) do |dir|
        result = described_class.call(csv_folder: dir)

        expect(result.updated_count).to eq(1)
        expect(result.rows_touched).to eq(1)
        expect(result.rows_matched).to eq(1)
        expect(result.rows_unmatched).to eq(0)
        expect(target_asset.reload.contentdm_collection).to eq(temple_photos_collection)
      end
    end

    it "quietly discards duplicate rows within the same csv when the collection is the same" do
      with_csv_folder(%w[duplicate_same_collection.csv]) do |dir|
        result = described_class.call(csv_folder: dir)

        expect(result.updated_count).to eq(1)
        expect(result.rows_touched).to eq(2)
        expect(result.rows_matched).to eq(1)
        expect(result.rows_unmatched).to eq(0)
        expect(result.rows_discarded).to eq(1)
        expect(target_asset.reload.contentdm_collection).to eq(temple_photos_collection)
      end
    end

    it "rejects when no csv files are present in the folder" do
      with_csv_folder([]) do |dir|
        expect {
          described_class.call(csv_folder: dir)
        }.to raise_error(ArgumentError, /No CSV files found/)
      end
    end

    it "applies configured csv precedence rules when filenames conflict across files" do
      with_csv_folder(%w[
        ambler_filenames.csv
        bulletin_photos_filenames.csv
        bulletin_photos_restricted_filenames.csv
        scrc_photographs_filenames.csv
      ]) do |dir|
        result = described_class.call(csv_folder: dir)

        expect(result.updated_count).to eq(2)
        expect(result.rows_touched).to eq(4)
        expect(result.rows_matched).to eq(2)
        expect(result.rows_unmatched).to eq(0)
        expect(result.rows_discarded).to eq(2)
        expect(bulletin_asset.reload.contentdm_collection).to eq(bulletin_photos_collection)
        expect(ambler_overlap_asset.reload.contentdm_collection).to eq(ambler_collection)
      end
    end

    it "still rejects unconfigured conflicting collection assignments for the same filename" do
      with_csv_folder(%w[part1.csv conflict_part2.csv]) do |dir|
        expect {
          described_class.call(csv_folder: dir)
        }.to raise_error(ArgumentError, /Conflicting collections for filename 'match-one\.tif'/)
      end
    end

    it "rejects collection names that are not already present" do
      with_csv_folder(%w[unknown_collection.csv]) do |dir|
        expect {
          described_class.call(csv_folder: dir)
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    it "writes unmatched filenames to a csv in tmp" do
      with_csv_folder(%w[unmatched_rows.csv]) do |dir|
        result = described_class.call(csv_folder: dir)

        expect(result.updated_count).to eq(1)
        expect(result.rows_touched).to eq(3)
        expect(result.rows_matched).to eq(1)
        expect(result.rows_unmatched).to eq(2)
        expect(result.rows_discarded).to eq(0)
        rows = CSV.read(described_class::NON_MATCHES_CSV_PATH)
        expect(rows).to eq([
          [ "File Name", "Collection" ],
          [ "missing-one.tif", "Temple Photos" ],
          [ "missing-two.tif", "Temple AV" ]
        ])
      end
    end
  end

  describe "#notes_update_sql" do
    it "uses a database-compatible function when checking for an existing note" do
      sql = described_class.new(csv_folder: FIXTURE_FOLDER).send(:notes_update_sql).to_s

      if ActiveRecord::Base.connection.adapter_name.downcase.include?("postgres")
        expect(sql).to include("strpos(notes")
        expect(sql).not_to include("instr(")
      else
        expect(sql).to include("instr(notes")
        expect(sql).not_to include("strpos(")
      end
    end
  end
end
