# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FileTreeUpdates", type: :request do
  let(:volume) { create(:volume) }
  let(:folder) { create(:isilon_folder, volume: volume) }
  let!(:asset)  { create(:isilon_asset, parent_folder: folder) }
  let!(:user)   { create(:user, email: "tester@temple.edu") }

  before { sign_in user }

  describe "PATCH /volumes/:id/file_tree_updates" do
    context "with an editable field" do
      it "updates and persists the asset" do
        patch file_tree_updates_volume_path(volume), params: {
          node_id: "a-#{asset.id}",
          node_type: "asset",
          field: "notes",
          value: "reviewed"
        }, as: :json

        expect(response).to have_http_status(:ok)
        expect(asset.reload.notes).to eq("reviewed")
      end
    end

    context "with an invalid node_id" do
      it "returns not found" do
        patch file_tree_updates_volume_path(volume), params: {
          node_id: "99999",
          node_type: "asset",
          field: "notes",
          value: "Test"
        }, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context "with a non-editable or invalid field" do
      it "returns an error and does not update the field" do
        patch file_tree_updates_volume_path(volume), params: {
          node_id: "a-#{asset.id}",
          node_type: "asset",
          field: "file_size",
          value: "hack"
        }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(asset.reload.file_size.to_s).not_to eq("hack")
      end

      it "also returns an error for completely invalid fields" do
        patch "/volumes/#{volume.id}/file_tree_updates", params: {
          node_id: "a-#{asset.id}",
          node_type: "asset",
          field: "not_a_column",
          value: "foo"
        }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["status"]).to eq("error")
      end
    end
  end
end
