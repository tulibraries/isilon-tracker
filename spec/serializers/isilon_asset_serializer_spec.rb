require "rails_helper"

RSpec.describe IsilonAssetSerializer do
  let(:volume) { create(:volume) }
  let(:folder) { create(:isilon_folder, volume: volume) }
  let(:status) { create(:migration_status, name: "Migration in progress") }
  let(:user)   { create(:user, name: "Alice") }

  it "serializes ids and labels for migration_status and assigned_to" do
    asset = create(
      :isilon_asset,
      parent_folder: folder,
      migration_status: status,
      assigned_to: user
    )

    data = described_class.new(asset).as_json

    expect(data[:migration_status_id]).to eq(status.id)
    expect(data[:migration_status]).to eq("Migration in progress")
    expect(data[:assigned_to_id]).to eq(user.id)
    expect(data[:assigned_to]).to eq("Alice")
  end

  it "emits unassigned for missing user" do
    asset = create(:isilon_asset, parent_folder: folder, assigned_to: nil, migration_status: status)
    data = described_class.new(asset).as_json

    expect(data[:assigned_to]).to eq("Unassigned")
  end
end
