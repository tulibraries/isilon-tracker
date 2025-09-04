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

    it 'applies all automation rules correctly during sync' do
      service = described_class.new(csv_path: csv_path)
      service.sync

      # Rule 1: Migrated directory
      migrated_asset = IsilonAsset.find_by(isilon_path: "/deposit/migrated-collection - Migrated/photo.jpg")
      expect(migrated_asset.migration_status).to eq(migrated_status)

      # Rule 2: DELETE directory
      delete_asset = IsilonAsset.find_by(isilon_path: "/deposit/SCRC Accessions/DELETE-temp/document.pdf")
      expect(delete_asset.migration_status).to eq(dont_migrate_status)

      # Rule 3: Duplicate outside main areas - NOW HANDLED BY SEPARATE TASK
      # Duplicates will get default status during sync, then updated by duplicate detector
      duplicate_asset = IsilonAsset.find_by(isilon_path: "/backup/duplicate.pdf")
      expect(duplicate_asset.migration_status).to eq(default_migration_status) # Changed expectation

      # Rule 4: Unprocessed TIFF (post-processing)
      unprocessed_asset = IsilonAsset.find_by(isilon_path: "/deposit/digitization/unprocessed/scan001.tiff")
      expect(unprocessed_asset.migration_status).to eq(dont_migrate_status)

      # No rules applied
      normal_asset = IsilonAsset.find_by(isilon_path: "/regular/normal-file.pdf")
      expect(normal_asset.migration_status).to eq(default_migration_status)
    end
  end
end
