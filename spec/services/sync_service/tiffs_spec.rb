# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncService::Tiffs, type: :service do
  let!(:deposit_volume) { FactoryBot.create(:volume, name: "deposit") }
  let!(:media_volume) { FactoryBot.create(:volume, name: "media-repository") }
  let!(:default_migration_status) { FactoryBot.create(:migration_status, :default) }
  let!(:dont_migrate_status) { FactoryBot.create(:migration_status, :dont_migrate) }

  describe '.call' do
    it 'creates new instance and calls process' do
      expect_any_instance_of(described_class).to receive(:process)
      described_class.call(volume_name: "deposit")
    end
  end

  describe '#initialize' do
    context 'with valid volume name' do
      it 'sets up for specific volume' do
        service = described_class.new(volume_name: "deposit")
        expect(service.instance_variable_get(:@volume_name)).to eq("deposit")
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

    context 'with invalid volume name' do
      it 'raises ArgumentError' do
        expect {
          described_class.new(volume_name: "nonexistent")
        }.to raise_error(ArgumentError, "Volume 'nonexistent' not found")
      end
    end
  end

  describe '#process' do
    # Set up test data with folder structure
    let!(:project1_folder) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/project1") }
    let!(:project1_processed) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/project1/processed", parent_folder: project1_folder) }
    let!(:project1_unprocessed) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/project1/unprocessed", parent_folder: project1_folder) }

    let!(:project2_folder) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/project2") }
    let!(:project2_processed) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/project2/processed", parent_folder: project2_folder) }
    let!(:project2_raw) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/project2/raw", parent_folder: project2_folder) }

    # Create TIFF assets - Project 1: Equal counts (2 processed, 2 unprocessed)
    let!(:project1_assets) do
      [
        FactoryBot.create(:isilon_asset, parent_folder: project1_processed, isilon_path: "/deposit/project1/processed/image001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_processed, isilon_path: "/deposit/project1/processed/image002.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_unprocessed, isilon_path: "/deposit/project1/unprocessed/image001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_unprocessed, isilon_path: "/deposit/project1/unprocessed/image002.tiff", file_type: "TIFF", migration_status: default_migration_status)
      ]
    end

    # Create TIFF assets - Project 2: Unequal counts (1 processed, 2 raw)
    let!(:project2_assets) do
      [
        FactoryBot.create(:isilon_asset, parent_folder: project2_processed, isilon_path: "/deposit/project2/processed/scan001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project2_raw, isilon_path: "/deposit/project2/raw/scan001.tiff", file_type: "TIFF", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project2_raw, isilon_path: "/deposit/project2/raw/scan002.tiff", file_type: "TIFF", migration_status: default_migration_status)
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
          "/deposit/project1/unprocessed/image001.tiff",
          "/deposit/project1/unprocessed/image002.tiff"
        ])
        expect(project1_unprocessed.all? { |asset| asset.migration_status == dont_migrate_status }).to be true

        # Project 2: 1 processed, 2 raw - should NOT change (counts don't match)
        project2_raw = IsilonAsset.where(isilon_path: [
          "/deposit/project2/raw/scan001.tiff",
          "/deposit/project2/raw/scan002.tiff"
        ])
        expect(project2_raw.all? { |asset| asset.migration_status == default_migration_status }).to be true
      end
    end

    context 'when processing specific volume' do
      it 'only processes TIFFs in the specified volume' do
        service = described_class.new(volume_name: "deposit")
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

        service = described_class.new(volume_name: "deposit")
        result = service.process

        expect(result.success?).to be true
        expect(result.tiff_comparisons_updated).to eq(0)
        expect(result.migration_statuses_updated).to eq(0)
      end
    end

    context 'when "Don\'t migrate" status is missing' do
      before { dont_migrate_status.destroy }

      it 'completes successfully but logs error and updates nothing' do
        service = described_class.new(volume_name: "deposit")

        # Allow all normal log messages to pass through
        allow(service).to receive(:stdout_and_log).and_call_original

        # Expect the specific error message to be logged at least once
        expect(service).to receive(:stdout_and_log).with(
          "ERROR: 'Don't migrate' status not found",
          level: :error
        ).at_least(:once).and_call_original

        result = service.process

        # Service completes successfully but doesn't update anything
        expect(result.success?).to be true
        expect(result.migration_statuses_updated).to eq(0)
      end
    end
  end

  describe '#extract_parent_directory' do
    let(:service) { described_class.new }

    it 'extracts parent from processed path' do
      path = "/deposit/project1/processed/image.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project1")
    end

    it 'extracts parent from unprocessed path' do
      path = "/deposit/project2/unprocessed/scan.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project2")
    end

    it 'extracts parent from raw path' do
      path = "/deposit/project3/raw/file.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project3")
    end

    it 'returns nil for invalid path' do
      path = "/deposit/project4/other/file.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to be_nil
    end

    it 'handles case insensitive matching' do
      path = "/deposit/PROJECT1/PROCESSED/image.tiff"
      result = service.send(:extract_parent_directory, path)
      expect(result).to eq("/deposit/project1")  # Method converts to lowercase for matching
    end
  end

  describe '#classify_subdirectory_type' do
    let(:service) { described_class.new }

    it 'classifies processed directory' do
      path = "/deposit/project1/processed/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to eq("processed")
    end

    it 'classifies unprocessed directory' do
      path = "/deposit/project1/unprocessed/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to eq("unprocessed")
    end

    it 'classifies raw directory as unprocessed' do
      path = "/deposit/project1/raw/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to eq("unprocessed")
    end

    it 'returns nil for other directories' do
      path = "/deposit/project1/other/image.tiff"
      result = service.send(:classify_subdirectory_type, path)
      expect(result).to be_nil
    end
  end

  describe '#build_base_tiff_query' do
    let(:service) { described_class.new }
    let!(:test_folder) { FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/test/processed") }

    it 'includes TIFF files by extension and file_type' do
      # Create test assets
      tiff_asset1 = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/deposit/test/processed/image.tiff")
      tiff_asset2 = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/deposit/test/processed/image.tif")
      tiff_asset3 = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/deposit/test/processed/image.jpg", file_type: "TIFF Image")
      pdf_asset = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/deposit/test/processed/doc.pdf")

      query = service.send(:build_base_tiff_query)
      results = query.pluck(:isilon_path)

      expect(results).to include(tiff_asset1.isilon_path)
      expect(results).to include(tiff_asset2.isilon_path)
      expect(results).to include(tiff_asset3.isilon_path)
      expect(results).not_to include(pdf_asset.isilon_path)
    end

    it 'filters to deposit folders' do
      other_folder = FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/other/test/processed")

      deposit_asset = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/deposit/test/processed/image.tiff")
      other_asset = FactoryBot.create(:isilon_asset, parent_folder: other_folder, isilon_path: "/other/test/processed/image.tiff")

      query = service.send(:build_base_tiff_query)
      results = query.pluck(:isilon_path)

      expect(results).to include(deposit_asset.isilon_path)
      expect(results).not_to include(other_asset.isilon_path)
    end

    it 'excludes scrc accessions' do
      scrc_folder = FactoryBot.create(:isilon_folder, volume: deposit_volume, full_path: "/deposit/scrc accessions/processed")

      regular_asset = FactoryBot.create(:isilon_asset, parent_folder: test_folder, isilon_path: "/deposit/regular/processed/image.tiff")
      scrc_asset = FactoryBot.create(:isilon_asset, parent_folder: scrc_folder, isilon_path: "/deposit/scrc accessions/processed/image.tiff")

      query = service.send(:build_base_tiff_query)
      results = query.pluck(:isilon_path)

      expect(results).to include(regular_asset.isilon_path)
      expect(results).not_to include(scrc_asset.isilon_path)
    end
  end

  describe 'error handling' do
    it 'returns error result when exception occurs' do
      service = described_class.new(volume_name: "deposit")

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
