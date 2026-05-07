require "rails_helper"

RSpec.describe "Session Timeout", type: :system, js: true do
  before do
    driven_by :cuprite
    visit new_user_session_path
    page.find("#flash-messages[data-controller*='session-timeout']", visible: :all)
  end

  it "shows a warning and lets the user extend the session" do
    original_expiration, renewed_expiration = page.evaluate_script(<<~JS)
      (function() {
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#flash-messages"),
          "session-timeout"
        );

        const originalExpiration = Math.floor(Date.now() / 1000) + 30;
        const renewedExpiration = originalExpiration + 600;

        controller.expiresAtValue = originalExpiration;
        controller.keepaliveUrlValue = "/users/session/keepalive";
        controller.warningOffsetValue = 60;
        controller.warningMessageValue = "#{I18n.t("session_timeout.warning_message")}";
        controller.staySignedInLabelValue = "#{I18n.t("session_timeout.stay_signed_in")}";
        controller.showWarning();

        window.fetch = () => Promise.resolve({
          ok: true,
          json: () => Promise.resolve({ expires_at: renewedExpiration })
        });

        return [originalExpiration, renewedExpiration];
      })();
    JS

    expect(page).to have_css(".alert-warning", text: expected_warning_message(60), wait: 1)

    click_button I18n.t("session_timeout.stay_signed_in")

    expect(page).to have_no_css(".alert-warning", wait: 1)
    expect(controller_expires_at).to eq(renewed_expiration)
    expect(controller_expires_at).to be > original_expiration
  end

  def controller_expires_at
    page.evaluate_script(<<~JS)
      (function() {
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#flash-messages"),
          "session-timeout"
        );

        return controller.expiresAtValue;
      })();
    JS
  end

  def expected_warning_message(seconds)
    I18n.t("session_timeout.warning_message", minutes: [ (seconds / 60.0).ceil, 1 ].max)
  end
end
