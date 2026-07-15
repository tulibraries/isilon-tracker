# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Volumes file tree endpoints", type: :request do
  let!(:volume) { create(:volume) }
  let!(:user)   { create(:user, email: "tester@temple.edu") }
  let!(:assignee) { create(:user, name: "Assigned User", email: "assigned@example.com") }
  let!(:migration_status) { create(:migration_status, :default) }

  before { sign_in user }

  let!(:root) do
    create(:isilon_folder, volume: volume, parent_folder: nil, full_path: "/LibraryBeta")
  end

  let!(:folder_a) do
    create(:isilon_folder, volume: volume, parent_folder: root,
           full_path: "#{root.full_path}/LibDigital")
  end

  let!(:folder_b) do
    create(:isilon_folder, volume: volume, parent_folder: folder_a,
           full_path: "#{folder_a.full_path}/TUL_OHIST")
  end

  let!(:folder_c) do
    create(:isilon_folder, volume: volume, parent_folder: folder_b,
           full_path: "#{folder_b.full_path}/Scans")
  end

  let!(:aspace_collection) { create(:aspace_collection, name: "Spec ASpace") }
  let!(:contentdm_collection) { create(:contentdm_collection, name: "Spec ContentDM") }

  let!(:asset) do
    create(:isilon_asset, parent_folder: folder_c,
           isilon_name: "scan_beta_001.tif",
           isilon_path: "#{folder_c.full_path}/scan_beta_001.tif",
           migration_status: migration_status,
           assigned_to: assignee,
           notes: "asset notes",
           aspace_collection: aspace_collection,
           contentdm_collection: contentdm_collection,
           preservica_reference_id: "pres-123",
           aspace_linking_status: true)
  end

  def parsed
    JSON.parse(response.body)
  end

  describe "GET /volumes/:id/file_tree_folders" do
    it "returns child folders for a given parent_folder_id" do
      get "/volumes/#{volume.id}/file_tree_folders.json", params: { parent_folder_id: root.id }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body).to be_a(Array)
      expect(body).to all(be_a(Hash))
      expect(body).to all(include("id", "folder", "parent_folder_id"))
      expect(body).to all(satisfy { |h| h["folder"] == true })

      returned_ids = body.map { |h| h["id"] }
      expect(returned_ids).to include(folder_a.id)
      expect(returned_ids).not_to include(asset.id)
    end

    it "handles root folders when parent_folder_id is nil" do
      get "/volumes/#{volume.id}/file_tree_folders.json", params: { parent_folder_id: nil }
      expect(response).to have_http_status(:ok)
      body = parsed
      ids = body.map { |h| h["id"] }
      expect(ids).to include(root.id)
    end

    let!(:folder) { create(:isilon_folder, volume: volume) }

    it "returns correct descendant_assets_count" do
      create_list(:isilon_asset, 3, parent_folder: folder)

      get file_tree_volume_path(volume, format: :json)

      json = JSON.parse(response.body)
      match = json.find { |h| h["id"] == folder.id }
      expect(match["descendant_assets_count"]).to eq(3)
    end

    it "omits asset-only rendering fields from folder payloads" do
      get file_tree_volume_path(volume, format: :json)

      expect(response).to have_http_status(:ok)

      match = parsed.find { |h| h["id"] == root.id }
      expect(match).to include(
        "folder" => true,
        "assigned_to" => "Unassigned",
        "key" => root.id.to_s,
        "notes" => nil
      )
      expect(match.keys).not_to include(
        "migration_status",
        "migration_status_id",
        "contentdm_collection_id",
        "aspace_collection_id",
        "preservica_reference_id",
        "aspace_linking_status",
        "url"
      )
    end
  end

  describe "GET /volumes/:id/file_tree_assets" do
    it "returns assets for a given parent_folder_id" do
      get "/volumes/#{volume.id}/file_tree_assets.json", params: { parent_folder_id: folder_c.id }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body).to be_a(Array)
      expect(body).to all(be_a(Hash))
      expect(body).to all(include("folder", "parent_folder_id", "path", "key"))
      expect(body).to all(satisfy { |h| h["folder"] == false })
      expect(body).to all(satisfy { |h| h["parent_folder_id"] == folder_c.id })

      keys = body.map { |h| h["key"] }
      expect(keys).to include("a-#{asset.id}")
      match = body.find { |h| h["key"] == "a-#{asset.id}" }
      expect(match["path"]).to eq([ root.id, folder_a.id, folder_b.id, folder_c.id ])
      expect(match["assigned_to"]).to eq(assignee.name)
      expect(match["assigned_to_id"]).to eq(assignee.id)
      expect(match["migration_status"]).to eq(migration_status.name)
      expect(match["migration_status_id"]).to eq(migration_status.id)
      expect(match["notes"]).to eq("asset notes")
      expect(match["aspace_collection_id"]).to eq(aspace_collection.id)
      expect(match["contentdm_collection_id"]).to eq(contentdm_collection.id)
      expect(match["preservica_reference_id"]).to eq("pres-123")
      expect(match["aspace_linking_status"]).to eq("t")
      expect(match["url"]).to end_with("/admin/isilon_assets/#{asset.id}")
    end
  end

  describe "GET /volumes/:id/file_tree_folders_search" do
    it "finds a nested folder and includes its ancestor path" do
      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { q: "tul_ohist" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body["total_count"]).to eq(1)
      expect(body["notes_match_count"]).to eq(0)

      match = body.fetch("results").find { |h| h["id"] == folder_b.id }

      expect(match).to be_present
      expect(match["folder"]).to eq(true)
      expect(match["id"]).to eq(folder_b.id)
      expect(match["path"]).to be_a(Array)
      expect(match["path"]).to eq([ root.id, folder_a.id ])
    end

    it "does not count descendant folders whose own title does not match" do
      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { q: "librarybeta" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body["total_count"]).to eq(1)
      expect(body.fetch("results").map { |h| h["id"] }).to include(root.id, folder_a.id, folder_b.id, folder_c.id)
    end

    it "returns empty array for no matches" do
      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { q: "nope-nope" }
      expect(response).to have_http_status(:ok)
      expect(parsed).to eq({
        "results" => [],
        "total_count" => 0,
        "notes_match_count" => 0
      })
    end

    it "filters folders by assigned_to" do
      folder_b.update!(assigned_to: assignee)

      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { assigned_to: assignee.id }
      expect(response).to have_http_status(:ok)

      body = parsed
      results = body.fetch("results")
      expect(results).to be_a(Array)
      expect(results.map { |h| h["id"] }).to include(folder_b.id)
      expect(results.map { |h| h["id"] }).not_to include(root.id)
    end

    it "finds a folder by notes content and reports notes match count" do
      folder_b.update!(notes: "special archive note")

      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { q: "archive note" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body["total_count"]).to eq(1)
      expect(body["notes_match_count"]).to eq(1)
      expect(body.fetch("results").map { |h| h["id"] }).to include(folder_b.id)
    end
  end

  describe "GET /volumes/:id/file_tree_assets_search" do
    it "finds a deep asset and returns path to its parent folder" do
      get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { q: "beta" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body).to include(
        "results" => be_a(Array),
        "total_count" => 1,
        "returned_count" => 1
      )

      match = body.fetch("results").find { |h| h["id"] == asset.id }

      expect(match).to be_present
      expect(match["folder"]).to eq(false)
      expect(match["parent_folder_id"]).to eq(folder_c.id)
      expect(match["path"]).to start_with([ root.id, folder_a.id, folder_b.id ])
      expect(match["path"].last).to eq(folder_c.id)
      expect(match["path"].length).to eq(4)
    end

    it "finds an asset by notes content" do
      get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { q: "asset notes" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body["total_count"]).to eq(1)
      expect(body["notes_match_count"]).to eq(1)
      expect(body["returned_count"]).to eq(1)
      expect(body.fetch("results").pluck("id")).to include(asset.id)
    end

    it "returns empty array when no assets match" do
      get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { q: "zzz-not-found" }
      expect(response).to have_http_status(:ok)
      expect(parsed).to eq({
        "notes_match_count" => 0,
        "results" => [],
        "total_count" => 0,
        "returned_count" => 0
      })
    end

    it "filters assets by duplicate status" do
      duplicate_asset = create(:isilon_asset,
        parent_folder: folder_c,
        isilon_name: "dup.txt",
        isilon_path: "#{folder_c.full_path}/dup.txt",
        has_duplicates: true)

      get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { is_duplicate: "true" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body["total_count"]).to eq(1)
      expect(body["returned_count"]).to eq(1)

      ids = body.fetch("results").map { |h| h["id"] }
      expect(ids).to include(duplicate_asset.id)
      expect(ids).not_to include(asset.id)
    end
  end
end
