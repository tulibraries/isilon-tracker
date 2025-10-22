require "rails_helper"

RSpec.describe "File tree column filters", type: :system, js: true do
  let!(:user) { create(:user, email: "tester@temple.edu") }
  let!(:default_migration_status) { create(:migration_status, :default) }
  let!(:migrated_status) { create(:migration_status, :migrated) }
  let!(:volume) { create(:volume) }
  let!(:root_folder) do
    create(:isilon_folder, :root, volume:, full_path: "/volume/#{volume.id}/root")
  end
  let!(:match_asset) do
    create(
      :isilon_asset,
      parent_folder: root_folder,
      migration_status: default_migration_status,
      isilon_name: "match_asset.txt",
      aspace_linking_status: true
    )
  end
  let!(:other_asset) do
    create(
      :isilon_asset,
      parent_folder: root_folder,
      migration_status: migrated_status,
      isilon_name: "unrelated_document.txt",
      aspace_linking_status: false
    )
  end

  before do
    driven_by :cuprite
    sign_in user
    visit volume_path(volume)
    expect(page).to have_selector("div#tree .wb-row", minimum: 1)
  end

  it "shows and hides the column filter popup when toggling the icon" do
    find("[data-command='filter']", match: :first).click
    expect(page).to have_selector(".wb-popup", visible: true)

    find("[data-command='filter']", match: :first).click
    expect(page).to have_no_selector(".wb-popup", visible: true)
  end

  it "closes the popup when clicking outside" do
    find("[data-command='filter']", match: :first).click
    expect(page).to have_selector(".wb-popup", visible: true)

    find("body").click
    expect(page).to have_no_selector(".wb-popup", visible: true)
  end

  it "shows only one popup at a time" do
    icons = all("[data-command='filter']")
    icons[0].click
    expect(page).to have_selector(".wb-popup", count: 1)

    icons[1].click
    expect(page).to have_selector(".wb-popup", count: 1)
  end

  it "allows switching between dim and hide filter modes" do
    expect(page).to have_selector("#filter-mode-toggle[disabled]")

    fill_in "tree-filter", with: match_asset.isilon_name

    expect(page).to have_selector("#tree.wb-ext-filter-dim")
    expect(page).to have_no_selector("#filter-mode-toggle[disabled]", wait: 10)

    find("#filter-mode-toggle").click
    expect(page).to have_selector("#tree.wb-ext-filter-hide")
    expect(page).to have_selector("#filter-mode-toggle.active")

    find("#filter-mode-toggle").click
    expect(page).to have_no_selector("#tree.wb-ext-filter-hide")
    expect(page).to have_selector("#tree.wb-ext-filter-dim")
  end

  it "clears column filter indicators when clearing all filters at once" do
    find(
      :xpath,
      "//span[contains(@class,'wb-col-title')][normalize-space()='ASpace linking status']/parent::span[contains(@class,'wb-col')]/i[@data-command='filter']",
      wait: 10
    ).click

    within(".wb-popup") do
      find("option", text: "True").select_option
    end
    page.execute_script("document.querySelector('.wb-popup select')?.dispatchEvent(new Event('change', { bubbles: true }))")

    expect(page).to have_selector(".wb-header [data-command='filter'].wb-helper-invalid", wait: 10)
    expect(page).to have_no_selector("#filter-mode-toggle[disabled]", wait: 10)

    click_button "Clear All Filters"

    expect(page).to have_no_selector(".wb-header [data-command='filter'].wb-helper-invalid", wait: 10)
    expect(page).to have_selector("#filter-mode-toggle[disabled]", wait: 10)
    expect(page).to have_no_selector("#tree.wb-ext-filter-dim", wait: 10)
  end
end
