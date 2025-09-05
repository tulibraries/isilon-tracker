# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IsilonAsset, type: :model do
  describe 'duplicate associations' do
    let!(:original_asset) { FactoryBot.create(:isilon_asset, isilon_name: 'original_file.jpg') }
    let!(:duplicate_asset) { FactoryBot.create(:isilon_asset, isilon_name: 'duplicate_file.jpg', duplicate_of: original_asset) }
    let!(:another_duplicate) { FactoryBot.create(:isilon_asset, isilon_name: 'another_duplicate.jpg', duplicate_of: original_asset) }

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
        expect(original_asset.duplicates).to include(duplicate_asset, another_duplicate)
        expect(original_asset.duplicates.count).to eq(2)
      end

      it 'returns empty collection when asset has no duplicates' do
        standalone_asset = FactoryBot.create(:isilon_asset, isilon_name: 'standalone_file.jpg')
        expect(standalone_asset.duplicates).to be_empty
      end
    end

    describe 'dependent: :nullify' do
      it 'sets duplicate_of_id to null when original asset is deleted' do
        original_asset.destroy

        duplicate_asset.reload
        expect(duplicate_asset.duplicate_of_id).to be_nil
      end
    end
  end
end
