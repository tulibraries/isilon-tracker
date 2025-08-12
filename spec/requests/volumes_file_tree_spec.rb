# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Volumes file tree endpoints", type: :request do
  let!(:volume) { create(:volume) }

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

  let!(:asset) do
    create(:isilon_asset, parent_folder: folder_c,
           isilon_name: "scan_beta_001.tif",
           isilon_path: "#{folder_c.full_path}/scan_beta_001.tif")
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
  end

describe "GET /volumes/:id/file_tree_assets" do
  it "returns assets for a given parent_folder_id" do
    get "/volumes/#{volume.id}/file_tree_assets.json", params: { parent_folder_id: folder_c.id }
    expect(response).to have_http_status(:ok)

    body = parsed
    expect(body).to be_a(Array)
    expect(body).to all(be_a(Hash))
    expect(body).to all(include("folder", "parent_folder_id"))
    expect(body).to all(satisfy { |h| h["folder"] == false })
    expect(body).to all(satisfy { |h| h["parent_folder_id"] == folder_c.id })
    expect(body).to all(satisfy { |h| h.key?("id") || h.key?("key") })

    names = body.map { |h| h["isilon_name"] || h["title"] }.compact
    expect(names).to include("scan_beta_001.tif")
  end
end

describe "GET /volumes/:id/file_tree_assets_search" do
  it "finds a deep asset and returns path to its parent folder" do
    get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { q: "beta" }
    expect(response).to have_http_status(:ok)

    body = parsed
    match = body.find { |h| (h["isilon_name"] || h["title"]).to_s.match?(/scan_beta_001\.tif/i) }
    expect(match).to be_present
    expect(match["folder"]).to eq(false)
    expect(match["parent_folder_id"]).to eq(folder_c.id)
    expect(match["path"]).to eq([ root.id, folder_a.id, folder_b.id, folder_c.id ])
  end
end

  describe "GET /volumes/:id/file_tree_folders_search" do
    it "finds a nested folder and includes its ancestor path" do
      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { q: "tul_ohist" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body).to be_a(Array)

      match = body.find do |h|
        name = h["title"] || File.basename(h["full_path"].to_s)
        name.to_s =~ /TUL_OHIST/i
      end

      expect(match).to be_present
      expect(match["folder"]).to eq(true)
      expect(match["id"]).to eq(folder_b.id)
      expect(match["path"]).to be_a(Array)
      expect(match["path"]).to eq([ root.id, folder_a.id ])
    end

    it "returns empty array for no matches" do
      get "/volumes/#{volume.id}/file_tree_folders_search.json", params: { q: "nope-nope" }
      expect(response).to have_http_status(:ok)
      expect(parsed).to eq([])
    end
  end

  describe "GET /volumes/:id/file_tree_assets_search" do
    it "finds a deep asset and returns path to its parent folder" do
      get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { q: "beta" }
      expect(response).to have_http_status(:ok)

      body = parsed
      expect(body).to be_a(Array)

      match = body.find do |h|
        (h["isilon_name"] || h["title"]).to_s.match?(/scan_beta_001\.tif/i)
      end

      expect(match).to be_present
      expect(match["folder"]).to eq(false)
      expect(match["parent_folder_id"]).to eq(folder_c.id)
      expect(match["path"]).to start_with([ root.id, folder_a.id, folder_b.id ])
      expect(match["path"].last).to eq(folder_c.id)
      expect(match["path"].length).to eq(4)
    end

    it "returns empty array when no assets match" do
      get "/volumes/#{volume.id}/file_tree_assets_search.json", params: { q: "zzz-not-found" }
      expect(response).to have_http_status(:ok)
      expect(parsed).to eq([])
    end
  end
end
