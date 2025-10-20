require "rails_helper"

RSpec.describe "File tree column filters", type: :system, js: true do
  let!(:volume) { create(:volume) }

  before do
    driven_by :cuprite
    sign_in user
  end

  let!(:user)   { create(:user, email: "tester@temple.edu") }
  let!(:volume) { create(:volume) }

  before do
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
end
