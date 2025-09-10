# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Dashboards", type: :request do
  let!(:user)   { create(:user, email: "tester@temple.edu") }

  before { sign_in user }

  describe "GET /show" do
    it "returns http success" do
      get root_path
      expect(response).to have_http_status(:success)
    end
  end
end
