require "rails_helper"

RSpec.describe "Wunderbaum folder vs asset rendering", type: :system do
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

  let!(:user)   { create(:user, email: "tester@temple.edu") }

  before do
    driven_by :cuprite
    sign_in user

    visit "/volumes/#{volume.id}"
  end

    it "renders only notes and assigned_to inputs for folders" do
      expect(page).to have_css(".wb-tree")
      expect(page).to have_css(".wb-row", text: "RootFolder")

      folder = page
        .all(".wb-row", visible: true)
        .find do |row|
          row.find(".wb-expander", match: :first) rescue false
        end

      expect(folder).to be_present

      expect(folder).to have_css("input[name='notes']")

      expect(folder).not_to have_css("select[name='migration_status']")
      expect(folder).not_to have_css("select[name='contentdm_collection_id']")
      expect(folder).not_to have_css("select[name='aspace_collection_id']")
      expect(folder).not_to have_css("input[type='checkbox']")
    end

    it "renders all inputs for assets" do
      expect(page).to have_css(".wb-row", text: "RootFolder")

      folder = page
        .all(".wb-row", visible: true)
        .find { |row| row.has_css?(".wb-expander") }

      folder.find(".wb-expander").click

      expect(page).to have_css(".wb-row", text: "my_asset.txt")

      asset = page
        .all(".wb-row", visible: true)
        .find { |row| row.has_css?("a.asset-link") }

      expect(asset).to be_present

      expect(asset).to have_css("input[name='notes']")

      expect(asset).to have_css("select[name='migration_status']")
      expect(asset).to have_css("select[name='contentdm_collection_id']")
      expect(asset).to have_css("select[name='aspace_collection_id']")
      expect(asset).to have_css("input[name='preservica_reference_id']")
      expect(asset).to have_css("input[type='checkbox']")
    end
  end
