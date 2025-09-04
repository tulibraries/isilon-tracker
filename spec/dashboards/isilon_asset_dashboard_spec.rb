# frozen_string_literal: true

require 'rails_helper'

RSpec.describe IsilonAssetDashboard, type: :dashboard do
  describe 'duplicate_of field configuration' do
    let(:dashboard) { IsilonAssetDashboard.new }

    it 'includes duplicate_of in ATTRIBUTE_TYPES' do
      expect(IsilonAssetDashboard::ATTRIBUTE_TYPES).to have_key(:duplicate_of)
      expect(IsilonAssetDashboard::ATTRIBUTE_TYPES).to have_key(:duplicates)
    end

    it 'shows duplicate_of on the show page' do
      expect(IsilonAssetDashboard::SHOW_PAGE_ATTRIBUTES).to include(:duplicate_of)
      expect(IsilonAssetDashboard::SHOW_PAGE_ATTRIBUTES).to include(:duplicates)
    end

    it 'does not allow editing duplicate_of in forms' do
      expect(IsilonAssetDashboard::FORM_ATTRIBUTES).not_to include(:duplicate_of)
      expect(IsilonAssetDashboard::FORM_ATTRIBUTES).not_to include(:duplicates)
    end

    it 'configures duplicate_of as a BelongsTo field with correct options' do
      field = IsilonAssetDashboard::ATTRIBUTE_TYPES[:duplicate_of]
      expect(field).to be_a(Administrate::Field::Deferred)
      expect(field.deferred_class).to eq(Administrate::Field::BelongsTo)
    end

    it 'configures duplicates as a HasMany field' do
      field = IsilonAssetDashboard::ATTRIBUTE_TYPES[:duplicates]
      expect(field).to be_a(Administrate::Field::Deferred)
      expect(field.deferred_class).to eq(Administrate::Field::HasMany)
    end
  end

  describe 'field display' do
    let(:original_asset) { create(:isilon_asset, isilon_name: 'original.jpg') }
    let(:duplicate_asset) { create(:isilon_asset, isilon_name: 'duplicate.jpg', duplicate_of: original_asset) }

    it 'displays the duplicate relationship correctly' do
      expect(duplicate_asset.duplicate_of).to eq(original_asset)
      expect(original_asset.duplicates).to include(duplicate_asset)
    end
  end
end
