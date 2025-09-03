# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncService::Assets, type: :service do
  let!(:volume) { FactoryBot.create(:volume, name: "test-volume") }
  let!(:default_migration_status) { MigrationStatus.create!(name: "Needs review", active: true, default: true) }
  let!(:migrated_status) { MigrationStatus.create!(name: "Migrated", active: true, default: false) }
  let!(:dont_migrate_status) { MigrationStatus.create!(name: "Don't migrate", active: true, default: false) }

  describe '#apply_automation_rules' do
    let(:csv_path) { file_fixture('automation_rules_sync.csv').to_s }
    let(:service) { described_class.new(csv_path: csv_path) }

    context 'Rule 1: Migrated directories in deposit' do
      let(:test_data) { CSV.read(file_fixture('rule_1_test_data.csv'), headers: true) }

      it 'applies "Migrated" status to files in migrated directories' do
        row_data = test_data[0] # Migrated directory in deposit
        row = { "Path" => row_data['Path'] }
        result = service.send(:apply_automation_rules, row)
        expect(result).to eq(migrated_status.id)
      end

      it 'does not apply to born-digital areas' do
        row_data = test_data[1] # Born-digital area with Migrated
        row = { "Path" => row_data['Path'] }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil
      end

      it 'does not apply to non-deposit areas' do
        row_data = test_data[2] # Non-deposit area with Migrated
        row = { "Path" => row_data['Path'] }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil
      end
    end

    context 'Rule 2: DELETE directories in born-digital areas' do
      let(:test_data) { CSV.read(file_fixture('rule_2_test_data.csv'), headers: true) }

      it 'applies "Don\'t migrate" status to files in DELETE directories' do
        row_data = test_data[0] # DELETE in born-digital area
        row = { "Path" => row_data['Path'] }
        result = service.send(:apply_automation_rules, row)
        expect(result).to eq(dont_migrate_status.id)
      end

      it 'does not apply to DELETE directories outside born-digital areas' do
        row_data = test_data[1] # DELETE outside born-digital area
        row = { "Path" => row_data['Path'] }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil
      end
    end

    context 'Rule 3: Duplicate assets NOT located in media-repository or deposit folders' do
      let(:test_data) { CSV.read(file_fixture('rule_3_test_data.csv'), headers: true) }

      # Set up the existing asset to be found within media-repository or deposit
      let!(:parent_folder) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/collection") }
      let!(:existing_asset) do
        # Use the hash from the first csv row to create the original
        duplicate_hash = test_data[0]['Hash']
        FactoryBot.create(:isilon_asset,
                          parent_folder: parent_folder,
                          isilon_path: "/deposit/collection/original.pdf",
                          file_checksum: duplicate_hash)
      end

      # Set up media-repository asset for cross-main-area testing
      let!(:media_folder) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/media-repository/project") }
      let!(:media_asset) do
        # Use the hash from the fourth csv row for cross-main-area test
        cross_hash = test_data[3]['Hash']
        FactoryBot.create(:isilon_asset,
                          parent_folder: media_folder,
                          isilon_path: "/media-repository/project/cross-main-area.pdf",
                          file_checksum: cross_hash)
      end

      it 'applies "Don\'t migrate" to duplicates outside deposit/media-repository folder' do
        row_data = test_data[0] # ingest asset with duplicate hash

        row = {
          "Path" => row_data['Path'],
          "Hash" => row_data['Hash']
        }
        result = service.send(:apply_automation_rules, row)
        expect(result).to eq(dont_migrate_status.id)
      end

      it 'does not apply status when duplicate exists in media-repository folder' do
        row_data = test_data[1] # File in deposit

        row = {
          "Path" => row_data['Path'],
          "Hash" => row_data['Hash']
        }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil # does not set migration status
      end

      it 'does not apply when in folders but no duplicate exists' do
        row_data = test_data[2] # No duplicate exists

        row = {
          "Path" => row_data['Path'],
          "Hash" => row_data['Hash']
        }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil
      end

      it 'does not apply when deposit file has duplicate in media-repository' do
        row_data = test_data[3] # File in deposit with duplicate in media-repository

        row = {
          "Path" => row_data['Path'],
          "Hash" => row_data['Hash']
        }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil # does not set migration status - both are main areas
      end
    end

    context 'No rules apply' do
      it 'returns nil for regular files' do
        row = { "Path" => "/test-volume/some-other-area/regular-file.pdf" }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil
      end
    end
  end

  describe '#apply_rule_4_post_processing' do
    let(:csv_path) { file_fixture('rule_4_post_processing.csv').to_s }

    # Create folder structure using FactoryBot
    let!(:project1_folder) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/project1") }
    let!(:project1_processed) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/project1/processed", parent_folder: project1_folder) }
    let!(:project1_unprocessed) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/project1/unprocessed", parent_folder: project1_folder) }

    let!(:project2_folder) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/project2") }
    let!(:project2_processed) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/project2/processed", parent_folder: project2_folder) }
    let!(:project2_raw) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit/project2/raw", parent_folder: project2_folder) }

    # Create assets using FactoryBot (simulating they were just imported)
    let!(:project1_assets) do
      [
        FactoryBot.create(:isilon_asset, parent_folder: project1_processed, isilon_path: "/deposit/project1/processed/image001.tiff", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_processed, isilon_path: "/deposit/project1/processed/image002.tiff", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_unprocessed, isilon_path: "/deposit/project1/unprocessed/image001.tiff", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project1_unprocessed, isilon_path: "/deposit/project1/unprocessed/image002.tiff", migration_status: default_migration_status)
      ]
    end

    let!(:project2_assets) do
      [
        FactoryBot.create(:isilon_asset, parent_folder: project2_processed, isilon_path: "/deposit/project2/processed/scan001.tiff", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project2_raw, isilon_path: "/deposit/project2/raw/scan001.tiff", migration_status: default_migration_status),
        FactoryBot.create(:isilon_asset, parent_folder: project2_raw, isilon_path: "/deposit/project2/raw/scan002.tiff", migration_status: default_migration_status)
      ]
    end

    it 'marks unprocessed TIFFs as "Don\'t migrate" when counts match' do
      service = described_class.new(csv_path: csv_path)
      service.send(:apply_rule_4_post_processing)

      # Project 1: 2 processed, 2 unprocessed - should mark unprocessed as "Don't migrate"
      project1_unprocessed_assets = IsilonAsset.where(isilon_path: [
        "/deposit/project1/unprocessed/image001.tiff",
        "/deposit/project1/unprocessed/image002.tiff"
      ])

      expect(project1_unprocessed_assets.all? { |asset| asset.migration_status == dont_migrate_status }).to be true
    end

    it 'does not mark unprocessed TIFFs when counts do not match' do
      service = described_class.new(csv_path: csv_path)
      service.send(:apply_rule_4_post_processing)

      # Project 2: 1 processed, 2 raw - should NOT mark raw as "Don't migrate"
      project2_raw_assets = IsilonAsset.where(isilon_path: [
        "/deposit/project2/raw/scan001.tiff",
        "/deposit/project2/raw/scan002.tiff"
      ])

      expect(project2_raw_assets.all? { |asset| asset.migration_status == default_migration_status }).to be true
    end
  end

  describe 'Integration test: full sync with automation' do
    let(:csv_path) { file_fixture('automation_rules_sync.csv').to_s }
    let(:integration_csv_data) { CSV.read(file_fixture('automation_rules_sync.csv'), headers: true) }

    # Setup for Rule 3: Create the original asset that the duplicate will be compared against
    let!(:integration_main_folder) { FactoryBot.create(:isilon_folder, volume: volume, full_path: "/deposit") }
    let!(:integration_original_asset) do
      # Find the original file data from CSV (row 2: /deposit/original.pdf)
      original_row = integration_csv_data.find { |row| row['Path'] == "/test-volume/deposit/original.pdf" }
      FactoryBot.create(:isilon_asset,
                        parent_folder: integration_main_folder,
                        isilon_path: "/deposit/original.pdf",
                        file_checksum: original_row['Hash'])
    end

    it 'applies all automation rules correctly during sync' do
      service = described_class.new(csv_path: csv_path)
      service.sync

      # Rule 1: Migrated directory
      migrated_asset = IsilonAsset.find_by(isilon_path: "/deposit/migrated-collection - Migrated/photo.jpg")
      expect(migrated_asset.migration_status).to eq(migrated_status)

      # Rule 2: DELETE directory
      delete_asset = IsilonAsset.find_by(isilon_path: "/deposit/SCRC Accessions/DELETE-temp/document.pdf")
      expect(delete_asset.migration_status).to eq(dont_migrate_status)

      # Rule 3: Duplicate outside main areas
      duplicate_asset = IsilonAsset.find_by(isilon_path: "/backup/duplicate.pdf")
      expect(duplicate_asset.migration_status).to eq(dont_migrate_status)

      # Rule 4: Unprocessed TIFF (post-processing)
      unprocessed_asset = IsilonAsset.find_by(isilon_path: "/deposit/digitization/unprocessed/scan001.tiff")
      expect(unprocessed_asset.migration_status).to eq(dont_migrate_status)

      # No rules applied
      normal_asset = IsilonAsset.find_by(isilon_path: "/regular/normal-file.pdf")
      expect(normal_asset.migration_status).to eq(default_migration_status)
    end
  end
end
