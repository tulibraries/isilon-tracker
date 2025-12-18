# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncService::Assets, type: :service do
  let!(:volume) { FactoryBot.create(:volume, name: "deposit") }
  let!(:default_migration_status) { FactoryBot.create(:migration_status, :default) }
  let!(:migrated_status) { FactoryBot.create(:migration_status, :migrated) }
  let!(:dont_migrate_status) { FactoryBot.create(:migration_status, :dont_migrate) }

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
        row = { "Path" => "/deposit/some-other-area/regular-file.pdf" }
        result = service.send(:apply_automation_rules, row)
        expect(result).to be_nil
      end
    end
  end

  describe 'Integration test: full sync with automation' do
    let(:csv_path) { file_fixture('automation_rules_sync.csv').to_s }

    it 'applies all automation rules correctly during sync' do
      service = described_class.new(csv_path: csv_path)
      service.sync

      # Rule 1: Migrated directory
      migrated_asset = IsilonAsset.find_by(isilon_path: "/migrated-collection - Migrated/photo.jpg")
      expect(migrated_asset.migration_status).to eq(migrated_status)

      # Rule 2: DELETE directory
      delete_asset = IsilonAsset.find_by(isilon_path: "/SCRC Accessions/DELETE-temp/document.pdf")
      expect(delete_asset.migration_status).to eq(dont_migrate_status)

      # Rule 3: Duplicate outside main areas - NOW HANDLED BY SEPARATE TASK
      # Duplicates will get default status during sync, then updated by duplicate detector
      duplicate_asset = IsilonAsset.find_by(isilon_path: "/backup/duplicate.pdf")
      expect(duplicate_asset.migration_status).to eq(default_migration_status) # Changed expectation

      # Rule 4: TIFF post-processing is now handled by separate SyncService::Tiffs task
      # Assets sync only applies Rules 1-3, TIFF processing happens later

      # No rules applied
      normal_asset = IsilonAsset.find_by(isilon_path: "/regular/normal-file.pdf")
      expect(normal_asset.migration_status).to eq(default_migration_status)

      # Root-level asset (no parent folders) should import successfully
      root_asset = IsilonAsset.find_by(isilon_path: "/root-level.txt")
      expect(root_asset).to be_present
      expect(root_asset.parent_folder_id).to be_nil
      expect(root_asset.migration_status).to eq(default_migration_status)
    end
  end

  describe '#find_or_create_folder_safely' do
    let(:csv_path) { file_fixture('automation_rules_sync.csv').to_s }
    let(:service) { described_class.new(csv_path: csv_path) }

    context 'when handling race conditions' do
      it 'handles concurrent folder creation gracefully' do
        volume_id = volume.id
        folder_path = "/test/concurrent/folder"

        # Simulate the race condition by stubbing find_or_create_by!
        # to raise RecordNotUnique the first time, then succeed
        allow(IsilonFolder).to receive(:find_or_create_by!).with(
          volume_id: volume_id,
          full_path: folder_path
        ).and_raise(ActiveRecord::RecordNotUnique.new("Duplicate key")).once

        # Create the folder that would be created by the "other process"
        existing_folder = IsilonFolder.create!(
          volume_id: volume_id,
          full_path: folder_path
        )

        # Stub the find_by to return the existing folder (simulating successful retry)
        allow(IsilonFolder).to receive(:find_by).with(
          volume_id: volume_id,
          full_path: folder_path
        ).and_return(existing_folder)

        # Test that our method handles the race condition gracefully
        result = service.send(:find_or_create_folder_safely, volume_id, folder_path)

        expect(result).to eq(existing_folder)
        expect(result.volume_id).to eq(volume_id)
        expect(result.full_path).to eq(folder_path)
      end

      it 'raises error when retries are exhausted' do
        volume_id = volume.id
        folder_path = "/test/failing/folder"

        # Stub to always raise RecordNotUnique and never find existing folder
        allow(IsilonFolder).to receive(:find_or_create_by!).with(
          volume_id: volume_id,
          full_path: folder_path
        ).and_raise(ActiveRecord::RecordNotUnique.new("Duplicate key"))

        allow(IsilonFolder).to receive(:find_by).with(
          volume_id: volume_id,
          full_path: folder_path
        ).and_return(nil)

        # Stub sleep to avoid actual delays in test
        allow(service).to receive(:sleep)

        expect {
          service.send(:find_or_create_folder_safely, volume_id, folder_path)
        }.to raise_error(ActiveRecord::RecordNotFound, /Could not find or create folder after 3 retries/)
      end

      it 'creates folder successfully on first try when no conflict' do
        volume_id = volume.id
        folder_path = "/test/no/conflict"

        result = service.send(:find_or_create_folder_safely, volume_id, folder_path)

        expect(result).to be_a(IsilonFolder)
        expect(result.volume_id).to eq(volume_id)
        expect(result.full_path).to eq(folder_path)
        expect(result.persisted?).to be true
      end
    end
  end
end
