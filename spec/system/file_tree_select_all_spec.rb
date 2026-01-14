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

  let!(:other_asset) do
    create(:isilon_asset,
      parent_folder: folder_a,
      isilon_name: "scan_gamma_001.tif",
      isilon_path:  "#{folder_a.full_path}/scan_gamma_001.tif"
    )
  end

  before do
    driven_by(:cuprite)
    sign_in user
    visit volume_path(volume)
  end

  it "shows inactive tooltip when no filter is active" do
    button = find("#select-all", visible: true)
    expect(button[:title]).to eq("Select all filtered results")
    button.click
    expect(page).to have_no_css(".wb-row.wb-selected", wait: 5)
  end

  it "selects only filtered matches and not all nodes" do
    fill_in "tree-filter", with: "beta"
    expect(page).to have_css(".wb-row.wb-match", text: "scan_beta_001.tif", wait: 10)
    expect(page).to have_no_css(".wb-row.wb-match", text: "scan_gamma_001.tif", wait: 10)

    find("#select-all").click

    expect(page).to have_css(".wb-row.wb-selected", text: "scan_beta_001.tif", wait: 10)
    expect(page).to have_no_css(".wb-row.wb-selected", text: "scan_gamma_001.tif", wait: 5)

    find("#select-all").click
    expect(page).to have_no_css(".wb-row.wb-selected", wait: 5)
  end

  it "selects lazy-loaded descendants when a folder is selected" do
    root_checkbox = find(:css, "#tree i.wb-checkbox", match: :first, wait: 10)
    folder_row = root_checkbox.find(:xpath, "ancestor::div[contains(@class,'wb-row')]")

    root_checkbox.click

    expect(folder_row[:class]).to include("wb-selected")

    folder_row.find("i.wb-expander", wait: 10).click

    if page.has_no_css?(".wb-row", text: "scan_beta_001.tif", wait: 5)
      second_expander = all("i.wb-expander", minimum: 1, wait: 10)[1]
      second_expander&.click
    end

    expect(page).to have_css(".wb-row", text: "scan_beta_001.tif", wait: 20)
    expect(page).to have_css(".wb-row", text: "scan_gamma_001.tif", wait: 20)

    expect(page).to have_css(".wb-row.wb-selected", text: "scan_beta_001.tif", wait: 20)
    expect(page).to have_css(".wb-row.wb-selected", text: "scan_gamma_001.tif", wait: 20)
  end

  it "shows and hides the loading banner during selection" do
    fill_in "tree-filter", with: "beta"
    button = find("#select-all")
    expect(page).to have_no_css(".wb-loading-container", visible: true)
    button.click
    expect(page).to have_css(".wb-loading-container", wait: 10)
    expect(page).to have_no_css(".wb-loading-container", wait: 20)
  end

  it "updates tooltip text based on selection state" do
    fill_in "tree-filter", with: "beta"
    expect(page).to have_css(".wb-row.wb-match", text: "scan_beta_001.tif", wait: 10)

    button = find("#select-all")

    expect(button[:title]).to eq("Select filtered items")

    button.click
    expect(button[:title]).to eq("Clear selection")

    button.click
    expect(button[:title]).to eq("Select filtered items")
  end
end
