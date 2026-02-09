# frozen_string_literal: true

require "rails_helper"

RSpec.describe "File tree duplicate column", type: :system, js: true do
  let!(:user) { create(:user, email: "tester@temple.edu") }
  let!(:volume) { create(:volume) }
  let!(:root_folder) do
    create(:isilon_folder, :root, volume:, full_path: "/volume/#{volume.id}/root")
  end
  let!(:duplicate_asset) do
    create(:isilon_asset, parent_folder: root_folder, isilon_name: "duplicate.txt", has_duplicates: true)
  end

  before do
    driven_by :cuprite
    sign_in user
    visit volume_path(volume)
    expect(page).to have_selector("#tree .wb-row", minimum: 1)
  end

  it "shows a duplicate tag for assets with duplicates" do
    within "#tree" do
      find("i.wb-expander", match: :first).click

      expect(page).to have_selector(".wb-row .wb-title", text: duplicate_asset.isilon_name, wait: 10)
      expect(page).to have_xpath(
        "//div[contains(@class,'wb-row')]" \
        "[.//span[contains(@class,'wb-title')][normalize-space()='#{duplicate_asset.isilon_name}']]" \
        "//span[contains(@class,'duplicate-tag')][normalize-space()='Duplicate']",
        wait: 10
      )
    end
  end
end
