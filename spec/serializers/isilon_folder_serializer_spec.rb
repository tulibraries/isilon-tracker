require "rails_helper"

RSpec.describe IsilonFolderSerializer do
  let(:volume) { create(:volume) }

  it "serializes assigned_to label and id" do
    user = create(:user, name: "Bob")
    folder = create(:isilon_folder, volume: volume, assigned_to: user)

    data = described_class.new(folder).as_json

    expect(data[:assigned_to_id]).to eq(user.id)
    expect(data[:assigned_to]).to eq("Bob")
  end

  it "emits Unassigned when no user" do
    folder = create(:isilon_folder, volume: volume, assigned_to: nil)

    data = described_class.new(folder).as_json

    expect(data[:assigned_to]).to eq("Unassigned")
  end
end
