require "rails_helper"

RSpec.describe "Session timeout data", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { FactoryBot.create(:user) }
  let(:warning_lead_time) { Rails.application.config.session_management.warning_lead_time.to_i }

  describe "GET /" do
    context "when the user is signed in" do
      it "exposes complete session timeout attributes" do
        travel_to(Time.zone.local(2024, 1, 1, 12, 0, 0)) do
          sign_in user

          get root_path
          expect(response).to have_http_status(:ok)

          container = Nokogiri::HTML(response.body).at_css("#flash-messages")

          expect(container["data-controller"]).to include("session-timeout")

          expect(container["data-session-timeout-expires-at-value"].to_i)
            .to eq((Time.current + Devise.timeout_in).to_i)
          expect(container["data-session-timeout-duration-value"].to_i)
            .to eq(Devise.timeout_in.to_i)
          expect(container["data-session-timeout-warning-offset-value"].to_i)
            .to eq(warning_lead_time)
          expect(container["data-session-timeout-keepalive-url-value"])
            .to eq(user_session_keepalive_path)
          expect(container["data-session-timeout-warning-message-value"])
            .to eq(I18n.t("session_timeout.warning_message"))
          expect(container["data-session-timeout-stay-signed-in-label-value"])
            .to eq(I18n.t("session_timeout.stay_signed_in"))
          expect(container["data-session-timeout-error-message-value"])
            .to eq(I18n.t("session_timeout.error_message"))
          expect(container["data-session-timeout-expired-message-value"])
            .to eq(I18n.t("session_timeout.expired_message"))
        end
      end
    end

    context "when the user is signed out" do
      it "limits data attributes to controller registration" do
        get new_user_session_path
        expect(response).to have_http_status(:ok)

        container = Nokogiri::HTML(response.body).at_css("#flash-messages")

        expect(container["data-controller"]).to eq("session-timeout")
        expect(
          container.attribute_nodes.map(&:name)
        ).to contain_exactly("id", "data-controller")
      end
    end
  end
end
