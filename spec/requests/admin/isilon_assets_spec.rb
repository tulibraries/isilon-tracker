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

  it "renders assigned_to with the user title on the show page" do
    assignee = FactoryBot.create(:user, name: "Assigned User")
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      assigned_to: assignee
    )

    get admin_isilon_asset_path(asset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assigned to")
    expect(response.body).to include("Assigned User")
  end

  it "renders last_updated_by using the matching user title on the show page" do
    updater = FactoryBot.create(:user, name: "Updater User")
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      last_updated_by: updater.id.to_s
    )

    get admin_isilon_asset_path(asset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Last updated by")
    expect(response.body).to include("Updater User")
  end

  it "renders assigned_to select but omits last_updated_by on the edit form" do
    assignee = FactoryBot.create(:user, name: "Assigned User")
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      assigned_to: assignee,
      last_updated_by: assignee.id.to_s
    )

    get edit_admin_isilon_asset_path(asset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Assigned to")
    expect(response.body).to include("Assigned User")
    expect(response.body).not_to include("Last updated by")
  end

  it "allows clearing assigned_to on update" do
    assignee = FactoryBot.create(:user, name: "Assigned User")
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      assigned_to: assignee
    )

    patch admin_isilon_asset_path(asset), params: {
      isilon_asset: {
        assigned_to_id: ""
      }
    }

    expect(response).not_to have_http_status(:internal_server_error)
    expect(asset.reload.assigned_to).to be_nil
  end

  it "renders file size in a human-readable format on the show page" do
    asset = IsilonAsset.create!(
      isilon_name: "Test Asset",
      isilon_path: "/foo/bar/",
      file_size: "2048"
    )

    get admin_isilon_asset_path(asset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("File size")
    expect(response.body).to include("2 KB")
  end

  it "renders duplicate rows with assigned_to and migration status" do
    assignee = FactoryBot.create(:user, name: "Assigned User")
    status = FactoryBot.create(:migration_status, name: "Needs Review")
    asset = IsilonAsset.create!(
      isilon_name: "Primary Asset",
      isilon_path: "/foo/bar/",
      migration_status: status
    )
    duplicate = IsilonAsset.create!(
      isilon_name: "Duplicate Asset",
      isilon_path: "/foo/baz/",
      assigned_to: assignee,
      migration_status: status
    )
    group = DuplicateGroup.create!(checksum: "abc")
    DuplicateGroupMembership.create!(duplicate_group: group, isilon_asset: asset)
    DuplicateGroupMembership.create!(duplicate_group: group, isilon_asset: duplicate)

    get admin_isilon_asset_path(asset)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Path (with volume)")
    expect(response.body).to include("Assigned to")
    expect(response.body).to include("Migration status")
    expect(response.body).to include("Assigned User")
    expect(response.body).to include("Needs Review")
  end
end
