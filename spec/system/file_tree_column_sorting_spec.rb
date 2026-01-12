require "rails_helper"

RSpec.describe "Volume file tree column sorting", type: :system do
  let!(:user)   { create(:user, email: "tester@temple.edu") }
  let!(:volume) { create(:volume) }

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
      full_path: "/LibraryBeta/AlphaFolder"
    )
  end

  let!(:folder_b) do
    create(:isilon_folder,
      volume: volume,
      parent_folder: root,
      full_path: "/LibraryBeta/ZuluFolder"
    )
  end

  before do
    driven_by(:cuprite)
    sign_in user
    visit volume_path(volume)
  end

  it "sorts filename column ascending" do
    header = find(".wb-header .wb-col", text: "Filename", wait: 10)

    header.click

    rows = all(".wb-row .wb-title").map(&:text)
    expect(rows).to eq(rows.sort)
  end

  it "sorts filename column descending" do
    header = find(".wb-header .wb-col", text: "Filename", wait: 10)

    header.click
    header.click

    rows = all(".wb-row .wb-title").map(&:text)
    expect(rows).to eq(rows.sort.reverse)
  end

  it "sorts assigned_to column ascending" do
    header = find(".wb-header .wb-col", text: "Assigned To", wait: 10)

    header.click

    values = all(".wb-row [data-colid='assigned_to']").map(&:text)
    expect(values).to eq(values.sort)
  end

  it "sorts assigned_to column descending" do
    header = find(".wb-header .wb-col", text: "Assigned To", wait: 10)

    header.click
    header.click

    values = all(".wb-row [data-colid='assigned_to']").map(&:text)
    expect(values).to eq(values.sort.reverse)
  end
end
