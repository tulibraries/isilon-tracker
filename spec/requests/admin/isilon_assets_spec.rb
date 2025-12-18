# spec/requests/admin/isilon_assets_spec.rb
require 'rails_helper'

RSpec.describe "Admin::IsilonAssets", type: :request do
  let!(:migration_status) { FactoryBot.create(:migration_status, :migrated) }

  let!(:aspace_collection) { AspaceCollection.create!(name: "Aspace Foo", active: true) }

  let!(:contentdm_collection) { ContentdmCollection.create!(name: "Contentdm Foo", active: true) }

  let!(:user) { FactoryBot.create(:user) }

  before do
    sign_in user  # ⬅️ Sign in the user before each request
  end


  it "renders the edit form with migration_status select" do
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      migration_status: migration_status
    )

    get edit_admin_isilon_asset_path(asset)
    expect(response.body).to include("Migration status")
    expect(response.body).to include("Migrated")
  end

  it "renders the edit form with aspace collection select" do
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      aspace_collection: aspace_collection
    )

    get edit_admin_isilon_asset_path(asset)
    expect(response.body).to include("Aspace collection")
    expect(response.body).to include("Aspace Foo")
  end

  it "renders the edit form with contentdm collection select" do
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      contentdm_collection: contentdm_collection
    )

    get edit_admin_isilon_asset_path(asset)
    expect(response.body).to include("Contentdm collection")
    expect(response.body).to include("Contentdm Foo")
  end
end
