# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IsilonAsset, type: :model do
  describe 'duplicate handling' do
    let!(:original_asset) { FactoryBot.create(:isilon_asset, isilon_name: 'original_file.jpg', file_checksum: 'abc123') }
    let!(:duplicate_asset) { FactoryBot.create(:isilon_asset, isilon_name: 'duplicate_file.jpg', duplicate_of: original_asset, file_checksum: 'abc123') }
    let!(:second_linked_duplicate) { FactoryBot.create(:isilon_asset, isilon_name: 'duplicate_file_two.jpg', duplicate_of: original_asset, file_checksum: 'abc123') }
    let!(:checksum_only_asset) { FactoryBot.create(:isilon_asset, isilon_name: 'checksum_match.jpg', file_checksum: 'abc123') }

    describe 'belongs_to :duplicate_of' do
      it 'allows an asset to reference another asset as its duplicate source' do
        expect(duplicate_asset.duplicate_of).to eq(original_asset)
      end

      it 'is optional - assets can exist without being duplicates' do
        expect(original_asset.duplicate_of).to be_nil
      end
    end

    describe '#duplicates' do
      it 'returns assets that share the same checksum, excluding the asset itself' do
        expect(original_asset.duplicates).to contain_exactly(duplicate_asset, second_linked_duplicate, checksum_only_asset)
      end

      it 'returns an empty relation when checksum is blank' do
        standalone_asset = FactoryBot.create(:isilon_asset, isilon_name: 'standalone_file.jpg', file_checksum: nil)
        expect(standalone_asset.duplicates).to be_empty
      end
    end

    describe 'has_many :linked_duplicates' do
      it 'tracks explicitly linked duplicates' do
        expect(original_asset.linked_duplicates).to include(duplicate_asset, second_linked_duplicate)
        expect(original_asset.linked_duplicates.count).to eq(2)
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
