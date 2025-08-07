require "rails_helper"

RSpec.describe "Admin IsilonFolder dashboard", type: :feature do
  let!(:folder) { FactoryBot.create(:isilon_folder) }
  let!(:asset) { FactoryBot.create(:isilon_asset) }
  let!(:volume) { FactoryBot.create(:volume) }
  let!(:user) { FactoryBot.create(:user) }

  before do
    login_as(user, scope: :user)
  end

  it "folder: does not show the destroy link" do
    visit admin_isilon_folders_path
    visit admin_isilon_folder_path(folder)
    expect(page).not_to have_link("Destroy")
    expect(page).not_to have_link("New isilon folder")
  end

  it "folder: does show the edit link" do
    visit admin_isilon_folders_path
    expect(page).to have_link("Edit")
    visit admin_isilon_folder_path(folder)
    expect(page).to have_link("Edit")
    expect(page).not_to have_link("New isilon folder")
  end

  it "asset: does not show the destroy link" do
    visit admin_isilon_assets_path
    expect(page).not_to have_link("Destroy")
    visit admin_isilon_asset_path(asset)
    expect(page).not_to have_link("Destroy")
    expect(page).not_to have_link("New isilon asset")
  end

  it "asset: does show the edit link" do
    visit admin_isilon_assets_path
    expect(page).to have_link("Edit")
    visit admin_isilon_asset_path(asset)
    expect(page).to have_link("Edit")
    expect(page).not_to have_link("New isilon asset")
  end

  it "volume: does not show the destroy link" do
    visit admin_volumes_path
    expect(page).not_to have_link("Destroy")
    visit admin_volume_path(volume)
    expect(page).not_to have_link("Destroy")
    expect(page).not_to have_link("New volume")
  end

  it "volume: does not show the edit link" do
    visit admin_volumes_path
    expect(page).not_to have_link("Edit")
    visit admin_volume_path(volume)
    expect(page).not_to have_link("Edit")
    expect(page).not_to have_link("New volume")
  end
end
