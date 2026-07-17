require "rails_helper"

RSpec.describe "Users", type: :request do
  describe "GET /users.json" do
    let(:current_user) do
      create(
        :user,
        status: :active,
        name: "Current User"
      )
    end

    let!(:active_user) do
      create(
        :user,
        status: :active,
        name: "Active Person"
      )
    end

    let!(:inactive_user) do
      create(
        :user,
        status: :inactive,
        name: "Inactive Person"
      )
    end

    before do
      sign_in current_user
    end

    it "returns active users and excludes inactive users" do
      get "/users.json"

      expect(response).to have_http_status(:ok)

      users = JSON.parse(response.body)

      expect(users).to include(
        current_user.id.to_s => "Current User",
        active_user.id.to_s => "Active Person"
      )

      expect(users).not_to include(
        inactive_user.id.to_s
      )
    end

    it "uses the email when an active user has no name" do
      user_without_name = create(
        :user,
        status: :active,
        name: nil,
        email: "noname@example.com"
      )

      get "/users.json"

      users = JSON.parse(response.body)

      expect(users).to include(
        user_without_name.id.to_s =>
          "noname@example.com"
      )
    end
  end
end
