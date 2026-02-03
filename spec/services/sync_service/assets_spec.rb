# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SyncService::Assets, type: :service do
  let!(:volume) { FactoryBot.create(:volume, name: "deposit") }
  let!(:default_migration_status) { FactoryBot.create(:migration_status, :default) }
  describe 'Integration test: full sync' do
    let(:csv_path) { Rails.root.join("spec/fixtures/files/assets_sync.csv").to_s }

    it 'applies default migration status during sync' do
      service = described_class.new(csv_path: csv_path)
      service.sync

      normal_asset = IsilonAsset.find_by(isilon_name: "file.txt")
      expect(normal_asset).to be_present
      expect(normal_asset.isilon_path).to eq("/alpha/file.txt")
      expect(normal_asset.migration_status).to eq(default_migration_status)
    end
  end

  describe '#find_or_create_folder_safely' do
    let(:csv_path) { Rails.root.join("spec/fixtures/files/assets_sync.csv").to_s }
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
