# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Volume File Tree Access Denied", type: :system do
  before do
    driven_by :cuprite
  end

  let!(:user) do
    user = FactoryBot.create(:user)
  end

  let!(:volume) { create(:volume, name: "TestVol") }

  context "when unauthenticated" do
    before do
      logout(user)
    end

    it "allows access to the volume index" do
      visit volumes_path
      expect(page).to have_content(volume.name) # Use the variable inside the block
    end

    it "denies access to an individual volume page" do
      visit volume_path(volume)
      expect(page).to have_content("You need to sign in") # Replace with actual auth message
    end
  end

  context "when authenticated" do
    before do
      login_as(user)
    end

    after do
      logout(user)
    end

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

    it "renders the root volume path" do
      visit volume_path(volume)
      expect(page).to have_content(volume.name)
    end
  end
end
