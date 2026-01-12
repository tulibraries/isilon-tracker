require "rails_helper"

RSpec.describe "Volume file tree select all", type: :system do
  let!(:user)   { create(:user, email: "tester@temple.edu") }
  let!(:volume) { create(:volume) }
  let!(:root) do
    create(:isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "/LibraryBeta"
    )
  end

  let!(:folder_a) do
    create(:isilon_folder,
      volume: volume,
      parent_folder: root,
      full_path: "#{root.full_path}/LibDigital"
    )
  end

  let!(:asset) do
    create(:isilon_asset,
      parent_folder: folder_a,
      isilon_name: "scan_beta_001.tif",
      isilon_path:  "#{folder_a.full_path}/scan_beta_001.tif"
    )
  end

  before do
    driven_by(:cuprite)
    sign_in user
    visit volume_path(volume)
  end

  it "has initial tooltip text" do
    button = find("#select-all", visible: true)
    expect(button[:title]).to eq("Select all items")
  end

  it "selects all nodes on click" do
    find("#select-all[title='Select all items']", wait: 10)

    find("#select-all").click

    expect(page).to have_css(".wb-row.wb-selected", wait: 10)
  end

  it "clears selection on second click" do
    find("#select-all[title='Select all items']", wait: 10)

    button = find("#select-all")

    button.click
    expect(page).to have_css(".wb-row.wb-selected", wait: 10)

    button.click
    expect(page).to have_no_css(".wb-row.wb-selected", wait: 10)
  end

  it "updates tooltip text based on selection state" do
    button = find("#select-all")

    expect(button[:title]).to eq("Select all items")

    button.click
    expect(button[:title]).to eq("Clear selection")

    button.click
    expect(button[:title]).to eq("Select all items")
  end
end
