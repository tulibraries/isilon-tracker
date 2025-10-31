# frozen_string_literal: true

require "rails_helper"

RSpec.describe ChecksumDuplicatesField, type: :field do
  describe "#data" do
    subject(:field_data) { field.data }

    let(:field) { described_class.new(:duplicates, resource.duplicates, :show, resource:) }

    context "when the resource has a checksum" do
      let(:resource) { create(:isilon_asset, file_checksum: "abc123", isilon_name: "primary.txt") }
      let!(:matching_asset_alpha) { create(:isilon_asset, file_checksum: resource.file_checksum, isilon_name: "alpha.txt") }
      let!(:matching_asset_beta) { create(:isilon_asset, file_checksum: resource.file_checksum, isilon_name: "beta.txt") }
      let!(:non_matching_asset) { create(:isilon_asset, file_checksum: "zzz999") }

      it "returns other assets that share the checksum" do
        expect(field_data).to contain_exactly(matching_asset_alpha, matching_asset_beta)
      end

      it "excludes the resource itself" do
        expect(field_data).not_to include(resource)
      end

      it "orders results by asset name" do
        expect(field_data.map(&:isilon_name)).to eq(%w[alpha.txt beta.txt])
      end
    end

    context "when the resource checksum is blank" do
      let(:resource) { create(:isilon_asset, file_checksum: nil) }

      it "returns an empty relation" do
        expect(field_data).to be_empty
      end
    end
  end
end
