require "rails_helper"

RSpec.describe "Wunderbaum folder vs asset rendering", type: :system do
  let!(:volume) { create(:volume, name: "TestVol") }

  let!(:root_folder) do
    create(
      :isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "RootFolder",
      has_descendant_assets: true
    )
  end

  let!(:empty_folder) do
    create(
      :isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "EmptyFolder",
      has_descendant_assets: false
    )
  end

  let!(:asset) do
    create(
      :isilon_asset,
      parent_folder: root_folder,
      isilon_name: "my_asset.txt"
    )
  end

  let!(:user) { create(:user, email: "tester@temple.edu") }

  before do
    driven_by :cuprite
    sign_in user
    visit volume_path(volume)
  end

  it "renders only allowed interactions for folders" do
    folder_row = page
      .all(".wb-row", visible: true)
      .find { |row| row.has_css?(".wb-expander") }

    expect(folder_row).to be_present

    expect(folder_row).to have_css("[data-colid='assigned_to']")
    expect(folder_row).to have_css("[data-colid='notes']")
    expect(folder_row).to have_css(".wb-select-like[data-colid='assigned_to']")

    expect(folder_row).not_to have_css("[data-colid='migration_status']")
    expect(folder_row).not_to have_css("[data-colid='contentdm_collection_id']")
    expect(folder_row).not_to have_css("[data-colid='aspace_collection_id']")
    expect(folder_row).not_to have_css("[data-colid='aspace_linking_status']")
  end

  it "renders all applicable columns for assets" do
    folder_row = page
      .all(".wb-row", visible: true)
      .find { |row| row.has_css?(".wb-expander") }

    folder_row.find(".wb-expander").click

    expect(page).to have_css(".wb-row", text: "my_asset.txt")

    asset_row = page
      .all(".wb-row", visible: true)
      .find { |row| row.has_css?("a.asset-link") }

    expect(asset_row).to be_present

    expect(asset_row).to have_css("input[name='notes']")
    expect(asset_row).to have_css("[data-colid='assigned_to']")
    expect(asset_row).to have_css("[data-colid='migration_status']")
    expect(asset_row).to have_css("[data-colid='contentdm_collection_id']")
    expect(asset_row).to have_css("[data-colid='aspace_collection_id']")
    expect(asset_row).to have_css("[data-colid='preservica_reference_id']")
    expect(asset_row).to have_css("input[type='checkbox']")
  end

  it "adds a class for empty folders" do
    empty_title = page
      .all(".wb-title", visible: true)
      .find { |title| title.text == "EmptyFolder" }

    expect(empty_title).to be_present
    expect(empty_title[:class]).to include("wb-title-empty")

    non_empty_title = page
      .all(".wb-title", visible: true)
      .find { |title| title.text == "RootFolder" }

    expect(non_empty_title).to be_present
    expect(non_empty_title[:class]).not_to include("wb-title-empty")
  end
end
