# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsilonFolderSerializer do
  it "includes the notes attribute" do
    folder = create(:isilon_folder, notes: "Serializer note")

    serialized = described_class.new(folder).serializable_hash

    expect(serialized[:notes]).to eq("Serializer note")
  end

  it "includes has_descendant_assets" do
    folder = create(:isilon_folder, has_descendant_assets: true)

    serialized = described_class.new(folder).serializable_hash

    expect(serialized[:has_descendant_assets]).to be(true)
  end
end
