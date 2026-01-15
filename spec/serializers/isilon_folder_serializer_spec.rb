# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsilonFolderSerializer do
  it "includes the notes attribute" do
    folder = create(:isilon_folder, notes: "Serializer note")

    serialized = described_class.new(folder).serializable_hash

    expect(serialized[:notes]).to eq("Serializer note")
  end
end
