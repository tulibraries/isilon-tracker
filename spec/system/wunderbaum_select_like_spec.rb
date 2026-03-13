require "rails_helper"

RSpec.describe "Wunderbaum select-like columns", type: :system do
  before do
    driven_by :cuprite
    sign_in user
  end

  let!(:volume) { create(:volume) }
  let!(:user) { create(:user, email: "tester@temple.edu") }
  let!(:assignee) { create(:user, name: "Alex Assign", email: "alex@example.com") }
  let!(:default_migration_status) { create(:migration_status, :default) }
  let!(:migrated_status) { create(:migration_status, :migrated) }
  let!(:root_folder) do
    create(:isilon_folder, :root, volume:, full_path: "/volume/#{volume.id}/root")
  end
  let!(:other_root_folder) do
    create(:isilon_folder, volume:, parent_folder: nil, full_path: "/volume/#{volume.id}/other-root")
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

  it "renders assigned_to as a human-readable label on initial load" do
    visit volume_path(volume)

    expect(page).to have_css(".wb-select-like", text: "Unassigned")
  end

  it "does not render native select elements on initial load" do
    visit volume_path(volume)

    expect(page).not_to have_css("select")
  end

  it "enters select edit mode when clicking a select-like cell" do
    visit volume_path(volume)

    cell = find(".wb-select-like", text: "Unassigned", match: :first)
    cell.click

    expect(page).to have_css(".wb-popup select")
  end

  it "updates the displayed label after selecting a new value" do
    visit volume_path(volume)

    find(".wb-select-like", text: "Unassigned", match: :first).click
    find("select").select("tester@temple.edu")

    expect(page).to have_css(".wb-select-like", text: "tester@temple.edu")
  end

  it "keeps the assignee label after another file tree selection rerenders the row" do
    visit volume_path(volume)

    root_row = find(
      :xpath,
      "//div[contains(@class,'wb-row')][.//span[contains(@class,'wb-title')][starts-with(normalize-space(.), 'root')]]",
      wait: 10
    )
    root_row.find("[data-colid='assigned_to']").click
    find(".wb-popup select").find("option", text: assignee.name).select_option
    page.execute_script("document.querySelector('.wb-popup select')?.dispatchEvent(new Event('change', { bubbles: true }))")

    expect(page).to have_css(".wb-row [data-colid='assigned_to'].wb-select-like", text: assignee.name, wait: 10)

    find(
      :xpath,
      "//div[contains(@class,'wb-row')][.//span[contains(@class,'wb-title')][starts-with(normalize-space(.), 'other-root')]]",
      wait: 10
    ).find("i.wb-checkbox").click

    updated_root_row = find(
      :xpath,
      "//div[contains(@class,'wb-row')][.//span[contains(@class,'wb-title')][starts-with(normalize-space(.), 'root')]]",
      wait: 10
    )
    expect(updated_root_row.find("[data-colid='assigned_to']").text).to eq(assignee.name)
  end

  it "stores assigned_to as unassigned when initially blank" do
    visit volume_path(volume)

    expect(page).to have_css(".wb-select-like", text: "Unassigned")
  end

  it "does not render aspace_linking_status checkbox for folder nodes" do
    visit volume_path(volume)

    folder_row = find(".wb-node", match: :first)

    within folder_row do
      expect(page).not_to have_css("input[type='checkbox']")
    end
  end

  it "renders aspace_linking_status checkbox for asset nodes" do
      visit volume_path(volume)

      expander = find("i.wb-expander", match: :first)
      expander.click

      expect(page).to have_css("input[type='checkbox']", wait: 10)
    end

  it "does not reintroduce static select elements after interaction" do
    visit volume_path(volume)

    find(".wb-select-like", match: :first).click
    find("select")

    expect(page).not_to have_css("select", count: 0)
  end
end
