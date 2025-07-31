# spec/requests/admin/isilon_assets_spec.rb
require 'rails_helper'

RSpec.describe "Admin::IsilonAssets", type: :request do
  let!(:migration_status) { MigrationStatus.create!(name: "Migrated", active: true) }

  it "renders the edit form with migration_status select" do
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      migration_status: migration_status
    )

    get edit_admin_isilon_asset_path(asset)
    expect(response.body).to include("Migration status") # crude, but works
    expect(response.body).to include("Migrated")
  end
end
