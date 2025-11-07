# frozen_string_literal: true

require "rails_helper"

RSpec.describe IsilonFolder, type: :model do
  let(:volume_one) { create(:volume) }
  let(:volume_two) { create(:volume) }

  it "allows the same full_path on different volumes" do
    create(:isilon_folder, volume: volume_one, full_path: "/Utilities")

    expect do
      create(:isilon_folder, volume: volume_two, full_path: "/Utilities")
    end.not_to raise_error
  end

  it "disallows duplicate full_path within the same volume" do
    create(:isilon_folder, volume: volume_one, full_path: "/Utilities")

    expect do
      create(:isilon_folder, volume: volume_one, full_path: "/Utilities")
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end
end
