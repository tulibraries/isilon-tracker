# spec/models/contentdm_collection_spec.rb
require 'rails_helper'

RSpec.describe AspaceCollection, type: :model do
  describe '#destroy' do
    it 'prevents deletion if referenced by isilon assets' do
      collection = AspaceCollection.create!(name: 'Test Collection')
      IsilonAsset.create!(
      isilon_name: "Example File",
      aspace_collection: collection,
      isilon_path: "/foo/bar",

    )

      expect(collection.destroy).to be_falsey
      expect(collection.errors[:base]).to include("Cannot delete record because dependent isilon assets exist")
    end

    it 'allows deletion if no referencing assets exist' do
      collection = ContentdmCollection.create!(name: 'Test Collection')

      expect { collection.destroy }.to change { ContentdmCollection.count }.by(-1)
    end
  end
end
