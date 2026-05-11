require "rails_helper"

RSpec.describe "Wunderbaum folder vs asset rendering", type: :system do
  let!(:volume) { create(:volume, name: "TestVol") }
  let!(:root_folder) do
    create(
      :isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "/TestVol/RootFolder"
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
  end

  it "renders only allowed interactions for folders" do
    visit volume_path(volume)

    folder_row = find(
      :xpath,
      "//div[contains(@class,'wb-row')][.//span[contains(@class,'wb-title')][normalize-space(text())='RootFolder']]",
      wait: 10
    )

    expect(folder_row).to have_css("[data-colid='assigned_to'].wb-select-like", text: "Unassigned")
    expect(folder_row).not_to have_css("a.asset-link")
    expect(folder_row).not_to have_css("input[type='checkbox']")

    folder_row.find(".wb-expander").click

    asset_row = find(
      :xpath,
      "//div[contains(@class,'wb-row')][.//a[contains(@class,'asset-link')][normalize-space(text())='my_asset.txt']]",
      wait: 10
    )

    expect(asset_row).to have_css("a.asset-link", text: "my_asset.txt")
    expect(asset_row).to have_css("input[name='notes']")
    expect(asset_row).to have_css("input[type='checkbox']")
  end
end
