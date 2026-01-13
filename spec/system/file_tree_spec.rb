# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Volume File Tree", type: :system, js: true do
  before do
    driven_by :cuprite
    sign_in user
  end

  let!(:user)   { create(:user, email: "tester@temple.edu") }
  let!(:volume) { create(:volume, name: "TestVol") }
  let!(:root_folder) do
    create(:isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "RootFolder"
    )
  end
  let!(:asset) do
    create(:isilon_asset,
      parent_folder: root_folder,
      isilon_name: "my_asset.txt"
    )
  end

  before do
    visit volume_path(volume)
    expect(page).to have_selector("div#tree .wb-row", minimum: 1)
  end

  it "renders the volume name on the page" do
    expect(page).to have_content("Volume: TestVol")
  end

  it "shows only folders before expanding" do
    within "div#tree" do
      expect(page).not_to have_content("my_asset.txt")
    end
  end

  it "renders asset titles as links when folder is expanded" do
    within "div#tree" do
      expect(page).to have_selector("div.wb-row", minimum: 1)
      expect(page).to have_selector("i.wb-expander")

      expander = find("i.wb-expander", match: :first)
      expander.click

      link = find("a", text: asset.isilon_name)
      expect(link[:href]).to end_with(admin_isilon_asset_path(asset))
      expect(link.text).to include(asset.isilon_name)
    end
  end

  it "opens asset links in a new tab" do
    expander = find("i.wb-expander", match: :first)
    expander.click

    link = find("a", text: asset.isilon_name)

    expect(link[:target]).to eq("_blank")
    expect(link[:rel]).to include("noopener")
  end

  it "allows checking the asset checkbox" do
    within "div#tree" do
      expect(page).to have_selector("div.wb-row", minimum: 1)
      expect(page).to have_selector("i.wb-expander")

      find("i.wb-expander", match: :first).click

      asset_row = find("div.wb-row", text: asset.isilon_name)
      checkbox = asset_row.find("input[type='checkbox']")
      checkbox.check
      expect(checkbox).to be_checked
    end
  end
end
