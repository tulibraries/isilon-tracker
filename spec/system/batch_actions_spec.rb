require 'rails_helper'

RSpec.describe "Batch Actions", type: :system, js: true do
  let!(:volume) { FactoryBot.create(:volume, name: "Test Volume") }
  let!(:folder) { FactoryBot.create(:isilon_folder, volume: volume) }
  let!(:user) { FactoryBot.create(:user) }
  let!(:other_user) { FactoryBot.create(:user) }
  let!(:migration_status_1) { FactoryBot.create(:migration_status, name: "Needs Review") }
  let!(:migration_status_2) { FactoryBot.create(:migration_status, name: "In Progress") }
  let!(:aspace_collection_1) { FactoryBot.create(:aspace_collection, name: "Collection A") }
  let!(:aspace_collection_2) { FactoryBot.create(:aspace_collection, name: "Collection B") }
  let!(:asset_1) { FactoryBot.create(:isilon_asset, parent_folder: folder) }
  let!(:asset_2) { FactoryBot.create(:isilon_asset, parent_folder: folder) }

  before do
    driven_by :cuprite
    sign_in user
    visit volume_path(volume)
  end

  describe "Batch Actions Buttons" do
    it "initially hides batch actions button" do
      expect(page).to have_css("#asset-batch-actions-btn", visible: false)
    end

    it "shows batch actions button when assets are selected" do
      # Wait for Stimulus controllers to load
      sleep 1

      # Simulate selecting assets via JavaScript
      page.execute_script(<<~JS)
        const event = new CustomEvent('wunderbaum:selectionChanged', {
          detail: { selectedAssetIds: [#{asset_1.id}, #{asset_2.id}] }
        });
        document.dispatchEvent(event);
      JS

      # Wait for JavaScript to process
      sleep 0.5

      expect(page).to have_css("#asset-batch-actions-btn", visible: true)
      expect(page).to have_content("Batch Actions (2)")
    end
  end

  describe "Asset Batch Actions Modal" do
    before do
      # Select assets and open modal
      page.execute_script(<<~JS)
        const event = new CustomEvent('wunderbaum:selectionChanged', {
          detail: { selectedAssetIds: [#{asset_1.id}, #{asset_2.id}] }
        });
        document.dispatchEvent(event);
      JS

      click_button "Batch Actions (2)"
    end

    it "opens modal when button is clicked" do
      expect(page).to have_css("#assetBatchActionsModal", visible: true)
    end

    it "displays all batch action options" do
      within "#assetBatchActionsModal" do
        expect(page).to have_select("migration_status_id")
        expect(page).to have_select("assigned_user_id")
        expect(page).to have_select("aspace_collection_id")
        expect(page).to have_select(
          "notes_action",
          with_options: [ "Unchanged", "Append", "Replace", "Clear (removes all notes)" ]
        )
        expect(page).to have_field("notes")
        expect(page).to have_field("aspace_linking_unchanged", checked: true)
      end
    end

    it "has proper form structure" do
      form = find("#assetBatchActionsModal form")
      expect(form["action"]).to include(volume_batch_actions_path(volume))
      expect(form["method"]).to eq("post")

      within "#assetBatchActionsModal" do
        expect(page).to have_css("input[name='asset_ids'][type='hidden']", visible: false)
        expect(page).to have_css("input[type='submit'][value='Apply Asset Updates']")
      end
    end
  end

  describe "Asset Form Interactions" do
    before do
      page.execute_script(<<~JS)
        const event = new CustomEvent('wunderbaum:selectionChanged', {
          detail: { selectedAssetIds: [#{asset_1.id}, #{asset_2.id}] }
        });
        document.dispatchEvent(event);
      JS

      click_button "Batch Actions (2)"
    end

    it "allows selecting different options" do
      within "#assetBatchActionsModal" do
        expect(page).to have_select("migration_status_id", with_options: [ "Unchanged", "Needs Review", "In Progress" ])
        expect(page).to have_select("assigned_user_id", with_options: [ "Unchanged", "Unassigned" ])
        expect(page).to have_select("aspace_collection_id", with_options: [ "Unchanged", "None", "Collection A", "Collection B" ])
      end
    end

    it "defaults to 'Unchanged' options" do
      within "#assetBatchActionsModal" do
        expect(page).to have_select("migration_status_id", selected: "Unchanged")
        expect(page).to have_select("assigned_user_id", selected: "Unchanged")
        expect(page).to have_select("aspace_collection_id", selected: "Unchanged")
        expect(page).to have_checked_field("aspace_linking_unchanged")
      end
    end
  end

  describe "JavaScript Integration" do
    it "loads the batch actions Stimulus controller" do
      expect(page).to have_css("[data-controller*='batch-actions']")
    end

    it "updates selection count dynamically for asset button" do
      # Initial state
      expect(page).to have_css("#asset-batch-actions-btn", visible: false)

      # Select one asset
      page.execute_script(<<~JS)
        const event = new CustomEvent('wunderbaum:selectionChanged', {
          detail: { selectedAssetIds: [#{asset_1.id}] }
        });
        document.dispatchEvent(event);
      JS

      expect(page).to have_content("Batch Actions (1)")

      # Select two assets
      page.execute_script(<<~JS)
        const event = new CustomEvent('wunderbaum:selectionChanged', {
          detail: { selectedAssetIds: [#{asset_1.id}, #{asset_2.id}] }
        });
        document.dispatchEvent(event);
      JS

      expect(page).to have_content("Batch Actions (2)")
    end
  end
end
