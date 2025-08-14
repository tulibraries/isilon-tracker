# frozen_string_literal: true

require "rails_helper"

RSpec.describe "file tree filtering", type: :system, js: true do
  before do
    driven_by :cuprite
    sign_in user
  end

  let!(:user)   { create(:user, email: "tester@temple.edu") }
  let!(:volume) { create(:volume) }

  # Build a deep folder chain and one asset at the leaf:
  # /LibraryBeta
  # └─ /LibraryBeta/LibDigital
  #    └─ /LibraryBeta/LibDigital/TUL_OHIST
  #       └─ /LibraryBeta/LibDigital/TUL_OHIST/Scans
  #           └─ scan_beta_001.tif
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

  let!(:folder_b) do
    create(:isilon_folder,
      volume: volume,
      parent_folder: folder_a,
      full_path: "#{folder_a.full_path}/TUL_OHIST"
    )
  end

  let!(:folder_c) do
    create(:isilon_folder,
      volume: volume,
      parent_folder: folder_b,
      full_path: "#{folder_b.full_path}/Scans"
    )
  end

  let!(:asset) do
    create(:isilon_asset,
      parent_folder: folder_c,
      isilon_name: "scan_beta_001.tif",
      isilon_path:  "#{folder_c.full_path}/scan_beta_001.tif"
    )
  end

  # Helper: visit the page that renders the Wunderbaum tree
  def visit_volume_tree
    # Adjust the path helper if your route differs
    visit volume_path(volume)
    # Wait until the root label is visible (tree mounted)
    expect(page).to have_content("/LibraryBeta")
  end

  it "shows deep matches (folders expand and asset appears) and clears the loading badge" do
    visit_volume_tree

    fill_in "tree-filter", with: "beta"

    # Loading indicator appears during hydration
    expect(page).to have_css(".wb-loading", text: /Loading|Searching/i)

    # The deep asset appears once its ancestor chain is expanded & assets loaded
    expect(page).to have_content("scan_beta_001.tif", wait: 12)

    # Ancestor folders now visible (expanded)
    expect(page).to have_content("LibDigital")
    expect(page).to have_content("TUL_OHIST")
    expect(page).to have_content("Scans")

    # Loading clears when finished
    expect(page).to have_no_css(".wb-loading", wait: 6)
  end

  it "collapses auto-expanded folders when the query is cleared" do
    visit_volume_tree

    fill_in "tree-filter", with: "beta"
    expect(page).to have_content("scan_beta_001.tif", wait: 12)

    # Clear query (your controller collapses expansions it opened)
    find("#tree-filter").send_keys(:escape)

    expect(page).to have_no_css(".wb-loading", wait: 6)
    expect(page).to have_no_content("scan_beta_001.tif", wait: 6)
    expect(page).to have_no_content("Scans", wait: 6)
  end

  it "cancels an in-flight search when the query changes quickly" do
    visit_volume_tree

    fill_in "tree-filter", with: "beta"

    # Immediately change/clear to trigger cancellation
    fill_in "tree-filter", with: ""

    # Badge disappears quickly and deep asset never shows
    expect(page).to have_no_css(".wb-loading", wait: 6)
    expect(page).to have_no_content("scan_beta_001.tif", wait: 6)
  end
end
