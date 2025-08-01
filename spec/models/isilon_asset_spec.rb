# spec/models/isilon_asset_spec.rb
require 'rails_helper'

RSpec.describe IsilonAsset, type: :model do
  let!(:migration_status) { MigrationStatus.create!(name: "Needs review", active: true, default: true) }

  it "can be created with a migration status" do
    asset = IsilonAsset.create!(
      isilon_name: "Example File",
      migration_status: migration_status,
      isilon_path: "/foo/bar",

    )
    expect(asset.migration_status.name).to eq("Needs review")
  end

  it "associates with an aspace collection" do
    collection = AspaceCollection.create!(name: "Photographs")
    asset = IsilonAsset.create!(
      isilon_name: "Example File",
      aspace_collection: collection,
      isilon_path: "/foo/bar",

    )
    expect(asset.aspace_collection.name).to eq("Photographs")
  end
]
  it "associates with an contentdm collection" do
    collection = ContentdmCollection.create!(name: "Photographs")
    asset = IsilonAsset.create!(
      isilon_name: "Example File",
      contentdm_collection: collection,
      isilon_path: "/foo/bar",

    )
    expect(asset.contentdm_collection.name).to eq("Photographs")
  end


]
  it "is valid with a migration_status_id" do
    asset = IsilonAsset.new(
      isilon_name: "Another File",
      migration_status_id: migration_status.id
    )
    expect(asset).to be_valid
  end

  it "is valid without a migration status if optional" do
    asset = IsilonAsset.new(isilon_name: "No status file")
    expect(asset).to be_valid
  end
end
