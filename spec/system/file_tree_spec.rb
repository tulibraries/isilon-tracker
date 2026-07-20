# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Volume File Tree", type: :system, js: true do
  def title_row(title_pattern)
    find(
      :xpath,
      "//div[contains(@class,'wb-row')][.//span[contains(@class,'wb-title')][#{title_pattern}]]",
      wait: 10
    )
  end

  def normalized_title_text(element)
    element.text.strip.sub(/\d+\z/, "")
  end

  before do
    driven_by :cuprite
    sign_in user
  end

  let!(:user)   { create(:user, email: "tester@temple.edu") }
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

  before do
    visit volume_path(volume)
    expect(page).to have_selector("div#tree .wb-row", minimum: 1)
  end

  it "renders the volume name on the page" do
    expect(page).to have_content("Volume: TestVol")
  end

  it "shows only folders before expanding" do
    within "div#tree" do
      expect(page).not_to have_content("my_asset.txt")
    end
  end

  it "renders asset titles as links when folder is expanded" do
    within "div#tree" do
      expect(page).to have_selector("div.wb-row", minimum: 1)
      expect(page).to have_selector("i.wb-expander")

      expander = find("i.wb-expander", match: :first)
      expander.click

      link = find("a", text: asset.isilon_name)
      expect(link[:href]).to end_with(admin_isilon_asset_path(asset))
      expect(link.text).to include(asset.isilon_name)
    end
  end

  it "opens asset links in a new tab" do
    expander = find("i.wb-expander", match: :first)
    expander.click

    link = find("a", text: asset.isilon_name)

    expect(link[:target]).to eq("_blank")
    expect(link[:rel]).to include("noopener")
  end

  it "allows checking the asset checkbox" do
    within "div#tree" do
      expect(page).to have_selector("div.wb-row", minimum: 1)
      expect(page).to have_selector("i.wb-expander")

      find("i.wb-expander", match: :first).click

      asset_row = find("div.wb-row", text: asset.isilon_name)
      checkbox = asset_row.find("input[type='checkbox']")
      checkbox.check
      expect(checkbox).to be_checked
    end
  end

  it "displays root and nested folders alphabetically" do
    create(
      :isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "Zulu Root"
    )

    create(
      :isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "Alpha Root"
    )

    parent = create(
      :isilon_folder,
      volume: volume,
      parent_folder: nil,
      full_path: "Middle Parent"
    )

    create(
      :isilon_folder,
      volume: volume,
      parent_folder: parent,
      full_path: "Middle Parent/Zulu Child"
    )

    create(
      :isilon_folder,
      volume: volume,
      parent_folder: parent,
      full_path: "Middle Parent/Alpha Child"
    )

    create(
      :isilon_folder,
      volume: volume,
      parent_folder: parent,
      full_path: "Middle Parent/Middle Child"
    )

    visit volume_path(volume)

    expect(page).to have_css(
      "#tree .wb-row .wb-title",
      text: "Alpha Root",
      wait: 10
    )

    root_titles = all("#tree .wb-row .wb-title", wait: 10).map do |element|
      normalized_title_text(element)
    end.select do |title|
      [ "Alpha Root", "Middle Parent", "Zulu Root" ].any? do |name|
        title.start_with?(name)
      end
    end

    expect(root_titles).to eq([ "Alpha Root", "Middle Parent", "Zulu Root" ])

    middle_parent_row = title_row("starts-with(normalize-space(.), 'Middle Parent')")

    middle_parent_row.find("i.wb-expander").click

    expect(page).to have_css(
      "#tree .wb-row .wb-title",
      text: "Alpha Child",
      wait: 10
    )

    child_titles = all("#tree .wb-row .wb-title", wait: 10).map do |element|
      normalized_title_text(element)
    end.select do |title|
      [ "Alpha Child", "Middle Child", "Zulu Child" ].any? do |name|
        title.start_with?(name)
      end
    end

    expect(child_titles).to eq([ "Alpha Child", "Middle Child", "Zulu Child" ])
  end
end
