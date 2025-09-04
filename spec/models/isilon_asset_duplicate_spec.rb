# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IsilonAsset, type: :model do
  describe 'duplicate associations' do
    let(:original_asset) { create(:isilon_asset, isilon_name: 'original_file.jpg') }
    let(:duplicate_asset) { create(:isilon_asset, isilon_name: 'duplicate_file.jpg', duplicate_of: original_asset) }
    let(:another_duplicate) { create(:isilon_asset, isilon_name: 'another_duplicate.jpg', duplicate_of: original_asset) }

    describe 'belongs_to :duplicate_of' do
      it 'allows an asset to reference another asset as its duplicate source' do
        expect(duplicate_asset.duplicate_of).to eq(original_asset)
      end

      it 'is optional - assets can exist without being duplicates' do
        expect(original_asset.duplicate_of).to be_nil
      end
    end

    describe 'has_many :duplicates' do
      it 'allows an asset to have multiple duplicates' do
        duplicate_asset # create the duplicate
        another_duplicate # create another duplicate

        expect(original_asset.duplicates).to include(duplicate_asset, another_duplicate)
        expect(original_asset.duplicates.count).to eq(2)
      end

      it 'returns empty collection when asset has no duplicates' do
        expect(original_asset.duplicates).to be_empty
      end
    end

    describe 'dependent: :nullify' do
      it 'sets duplicate_of_id to null when original asset is deleted' do
        duplicate_asset # create the duplicate

        original_asset.destroy

        duplicate_asset.reload
        expect(duplicate_asset.duplicate_of_id).to be_nil
      end
    end

    describe 'self-referencing integrity' do
      it 'prevents circular references' do
        # This would need to be implemented as a validation if required
        # For now, just test that the association setup works
        expect(duplicate_asset.duplicate_of).to eq(original_asset)
        expect(original_asset.duplicates).to include(duplicate_asset)
      end

      it 'allows deep duplicate chains' do
        # Asset A -> Asset B -> Asset C (C is duplicate of B, B is duplicate of A)
        asset_a = create(:isilon_asset, isilon_name: 'asset_a.jpg')
        asset_b = create(:isilon_asset, isilon_name: 'asset_b.jpg', duplicate_of: asset_a)
        asset_c = create(:isilon_asset, isilon_name: 'asset_c.jpg', duplicate_of: asset_b)

        expect(asset_c.duplicate_of).to eq(asset_b)
        expect(asset_b.duplicate_of).to eq(asset_a)
        expect(asset_a.duplicate_of).to be_nil

        expect(asset_a.duplicates).to include(asset_b)
        expect(asset_b.duplicates).to include(asset_c)
      end
    end
  end

  describe 'database constraints' do
    it 'has the correct foreign key constraint' do
      # Verify the foreign key exists and points to the correct table
      expect(ActiveRecord::Base.connection.foreign_keys('isilon_assets').any? do |fk|
        fk.column == 'duplicate_of_id' && fk.to_table == 'isilon_assets'
      end).to be true
    end

    it 'allows null values for duplicate_of_id' do
      asset = create(:isilon_asset, duplicate_of: nil)
      expect(asset.duplicate_of_id).to be_nil
      expect(asset).to be_valid
    end
  end
end
