# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncService::Tiffs, type: :service do
  let!(:deposit_volume) { FactoryBot.create(:volume, name: "Deposit") }
  let!(:media_volume) { FactoryBot.create(:volume, name: "Media-Repository") }
  let!(:default_migration_status) { FactoryBot.create(:migration_status, :default) }
  let!(:dont_migrate_status) { FactoryBot.create(:migration_status, :dont_migrate) }

  describe '.call' do
    it 'creates new instance and calls process' do
      expect_any_instance_of(described_class).to receive(:process)
      described_class.call(volume_name: "Deposit")
    end
  end

  describe '#initialize' do
    context 'with valid volume name' do
      it 'sets up for specific volume' do
        service = described_class.new(volume_name: "Deposit")
        expect(service.instance_variable_get(:@volume_name)).to eq("Deposit")
        expect(service.instance_variable_get(:@parent_volume)).to eq(deposit_volume)
      end
    end

    context 'with no volume name' do
      it 'sets up for all volumes' do
        service = described_class.new
        expect(service.instance_variable_get(:@volume_name)).to be_nil
        expect(service.instance_variable_get(:@parent_volume)).to be_nil
      end
    end

    context 'with unsupported volume name' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(volume_name: "nonexistent")
        }.to raise_error(ArgumentError, "Volume 'nonexistent' is not supported. Use one of: Deposit, Media-Repository")
      end
    end

    context 'with supported volume name missing from database' do
      before { deposit_volume.destroy }

      it 'raises ArgumentError when volume record not found' do
        expect {
          described_class.new(volume_name: "Deposit")
        }.to raise_error(ArgumentError, "Volume 'Deposit' not found")
      end
    end

    context 'with differently cased volume name' do
      it 'finds the volume case-insensitively' do
        service = described_class.new(volume_name: "deposit")
        expect(service.instance_variable_get(:@volume_name)).to eq("Deposit")
        expect(service.instance_variable_get(:@parent_volume)).to eq(deposit_volume)
      end
    end
  end

  describe '#process' do
    # Set up test data with folder structure
    let!(:project1_folder) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project1") }
    let!(:project1_processed) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project1/processed", parent_folder: project1_folder) }
    let!(:project1_processed_batch) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project1/processed/batch1", parent_folder: project1_processed) }
    let!(:project1_unprocessed) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project1/unprocessed", parent_folder: project1_folder) }
    let!(:project1_unprocessed_batch) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project1/unprocessed/batch1", parent_folder: project1_unprocessed) }

    let!(:project2_folder) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project2") }
    let!(:project2_processed) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project2/processed", parent_folder: project2_folder) }
    let!(:project2_processed_batch) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project2/processed/batch1", parent_folder: project2_processed) }
    let!(:project2_raw) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project2/raw", parent_folder: project2_folder) }
    let!(:project2_raw_batch) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/project2/raw/batch1", parent_folder: project2_raw) }

    # Create TIFF assets - Project 1: Equal counts (2 processed, 2 unprocessed)
    let!(:project1_assets) do
      [
        FactoryBot.create(:isilon_asset, parent_folder: project1_processed_batch, isilon_path: "/Deposit/project1/processed/batch1/image001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_processed_batch, isilon_path: "/Deposit/project1/processed/batch1/image002.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_unprocessed_batch, isilon_path: "/Deposit/project1/unprocessed/batch1/image001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_unprocessed_batch, isilon_path: "/Deposit/project1/unprocessed/batch1/image002.tiff", file_type: "TIFF", migration_status: default_migration_status)
      ]
    end

    # Create TIFF assets - Project 2: Unequal counts (1 processed, 2 raw)
    let!(:project2_assets) do
      [
        FactoryBot.create(:isilon_asset, parent_folder: project2_processed_batch, isilon_path: "/Deposit/project2/processed/batch1/scan001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project2_raw_batch, isilon_path: "/Deposit/project2/raw/batch1/scan001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project2_raw_batch, isilon_path: "/Deposit/project2/raw/batch1/scan002.tiff", file_type: "TIFF", migration_status: default_migration_status)
      ]
    end

    context 'when processing all volumes' do
      it 'marks unprocessed TIFFs as "Don\'t migrate" when counts match' do
        service = described_class.new
        result = service.process

        expect(result.success?).to be true
        expect(result.tiff_comparisons_updated).to eq(1)  # Only project1 has matching counts
        expect(result.migration_statuses_updated).to eq(2)  # 2 unprocessed TIFFs updated

        # Project 1: 2 processed, 2 unprocessed - should mark unprocessed as "Don't migrate"
        project1_unprocessed = IsilonAsset.where(isilon_path: [
          "/Deposit/project1/unprocessed/batch1/image001.tiff",
          "/Deposit/project1/unprocessed/batch1/image002.tiff"
        ])
        expect(project1_unprocessed.all? { |asset| asset.migration_status == dont_migrate_status }).to be true

        # Project 2: 1 processed, 2 raw - should NOT change (counts don't match)
        project2_raw = IsilonAsset.where(isilon_path: [
          "/Deposit/project2/raw/batch1/scan001.tiff",
          "/Deposit/project2/raw/batch1/scan002.tiff"
        ])
        expect(project2_raw.all? { |asset| asset.migration_status == default_migration_status }).to be true
      end
    end

    context 'when processing specific volume' do
      it 'only processes TIFFs in the specified volume' do
        service = described_class.new(volume_name: "Deposit")
        result = service.process

        expect(result.success?).to be true
        expect(result.tiff_comparisons_updated).to eq(1)
        expect(result.migration_statuses_updated).to eq(2)
      end
    end

    context 'when no matching TIFF patterns found' do
      it 'completes successfully with zero updates' do
        # Remove all TIFF assets
        IsilonAsset.destroy_all

        service = described_class.new(volume_name: "Deposit")
        result = service.process

        expect(result.success?).to be true
        expect(result.tiff_comparisons_updated).to eq(0)
        expect(result.migration_statuses_updated).to eq(0)
      end
    end

    context 'when "Don\'t migrate" status is missing' do
      before { dont_migrate_status.destroy }

      it 'completes successfully but logs error and updates nothing' do
        service = described_class.new(volume_name: "Deposit")

        result = service.process

        # Service completes successfully but doesn't update anything
        expect(result.success?).to be true
        expect(result.tiff_comparisons_updated).to eq(1)
        expect(result.migration_statuses_updated).to eq(0)
      end
    end
  end

  describe '#extract_parent_directory' do
    let(:service) { described_class.new }

    it 'extracts parent from processed path' do
      path = "/Deposit/project1/processed/image.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project1")
    end

    it 'extracts parent from unprocessed path' do
      path = "/Deposit/project2/unprocessed/scan.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project2")
    end

    it 'extracts parent from raw path' do
      path = "/Deposit/project3/raw/file.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project3")
    end

    it 'returns nil for invalid path' do
      path = "/Deposit/project4/other/file.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to be_nil
    end

    it 'handles case insensitive matching' do
      path = "/Deposit/PROJECT1/PROCESSED/image.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project1")  # Method normalizes to lowercase for matching
    end
  end

  describe '#classify_subdirectory_type' do
    let(:service) { described_class.new }

    it 'classifies processed directory' do
      path = "/Deposit/project1/processed/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to eq("processed")
    end

    it 'classifies unprocessed directory' do
      path = "/Deposit/project1/unprocessed/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to eq("unprocessed")
    end

    it 'classifies raw directory as unprocessed' do
      path = "/Deposit/project1/raw/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to eq("unprocessed")
    end

    it 'returns nil for other directories' do
      path = "/Deposit/project1/other/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to be_nil
    end
  end

  describe '#build_base_tiff_query' do
    let(:service) { described_class.new }
    let!(:test_folder) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/test/processed") }

    it 'includes TIFF files by extension and file_type' do
      # Create test assets
      tiff_asset1 = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/Deposit/test/processed/image.tiff")
      tiff_asset2 = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/Deposit/test/processed/image.tif")
      tiff_asset3 = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/Deposit/test/processed/image.jpg", file_type: "TIFF Image")
      pdf_asset = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/Deposit/test/processed/doc.pdf")

      query = service.send(:build_base_tiff_query)
      results = query.pluck(:isilon_path)

      expect(results).to include(tiff_asset1.isilon_path)
      expect(results).to include(tiff_asset2.isilon_path)
      expect(results).to include(tiff_asset3.isilon_path)
      expect(results).not_to include(pdf_asset.isilon_path)
    end

    it 'includes folders regardless of top-level prefix' do
      other_folder = FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/other/test/processed")

      deposit_asset = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/Deposit/test/processed/image.tiff")
      other_asset = FactoryBot.create(:isilon_asset, parent_folder: other_folder, isilon_path: "/other/test/processed/image.tiff")

      query = service.send(:build_base_tiff_query)
      results = query.pluck(:isilon_path)

      expect(results).to include(deposit_asset.isilon_path)
      expect(results).to include(other_asset.isilon_path)
    end

    it 'excludes scrc accessions' do
      scrc_folder = FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/Deposit/scrc accessions/processed")

      regular_asset = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/Deposit/regular/processed/image.tiff")
      scrc_asset = FactoryBot.create(:isilon_asset, parent_folder: scrc_folder, isilon_path: "/Deposit/scrc accessions/processed/image.tiff")

      query = service.send(:build_base_tiff_query)
      results = query.pluck(:isilon_path)

      expect(results).to include(regular_asset.isilon_path)
      expect(results).not_to include(scrc_asset.isilon_path)
    end
  end

  describe 'error handling' do
    it 'returns error result when exception occurs' do
      service = described_class.new(volume_name: "Deposit")

      # Simulate an error by stubbing build_base_tiff_query to raise an exception
      allow(service).to receive(:build_base_tiff_query).and_raise(StandardError.new("Database error"))

      result = service.process

      expect(result.success?).to be false
      expect(result.error_message).to include("Post-processing failed: Database error")
      expect(result.tiff_comparisons_updated).to eq(0)
      expect(result.migration_statuses_updated).to eq(0)
    end
  end
end
