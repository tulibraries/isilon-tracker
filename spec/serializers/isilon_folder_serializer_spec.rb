# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsilonFolderSerializer do
  it "includes the notes attribute" do
    folder = create(:isilon_folder, notes: "Serializer note")

    serialized = described_class.new(folder).serializable_hash

    expect(serialized[:notes]).to eq("Serializer note")
  end

  it "includes descendant_assets_count for folders" do
    folder = create(:isilon_folder, descendant_assets_count: 5)
    json = IsilonFolderSerializer.new(folder).as_json
    expect(json[:descendant_assets_count]).to eq(5)
  end
end
