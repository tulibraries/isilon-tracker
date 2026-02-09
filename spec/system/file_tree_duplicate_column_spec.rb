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
    page.execute_script(<<~JS)
      (() => {
        const start = Date.now();
        const tryExpand = () => {
          const el = document.querySelector("[data-controller~='wunderbaum']");
          const controller = window.Stimulus?.getControllerForElementAndIdentifier(el, "wunderbaum");
          const node = controller?._findNodeByKey?.("#{root_folder.id}");
          if (node && !node.expanded) {
            node.setExpanded(true);
            return;
          }
          if (Date.now() - start < 2000) setTimeout(tryExpand, 50);
        };
        tryExpand();
      })();
    JS

    expect(page).to have_selector(".wb-row .wb-title", text: duplicate_asset.isilon_name, wait: 10)

    title = find(".wb-row .wb-title", text: duplicate_asset.isilon_name, wait: 10)
    row = title.find(:xpath, "./ancestor::div[contains(@class,'wb-row')]")

    within(row) do
      expect(page).to have_selector(".duplicate-tag", text: "Duplicate", wait: 10, visible: :all)
    end
  end
end
