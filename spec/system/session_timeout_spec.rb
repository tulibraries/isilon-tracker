require "timeout"
require "rails_helper"

RSpec.describe "Session Timeout", type: :system, js: true do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { FactoryBot.create(:user, first_name: "Alex") }
  let(:warning_offset_seconds) { Rails.application.config.session_management.warning_lead_time.to_i }
  let(:session_timeout_seconds) { Devise.timeout_in.to_i }
  let(:base_time) { Time.zone.local(2024, 1, 1, 12, 0, 0) }

  before do
    travel_to(base_time)
    driven_by :cuprite
    sign_in user
    visit root_path
    wait_for_stimulus_application
    wait_for_session_timeout_controller
    sync_client_clock
  end

  after do
    restore_client_clock
    travel_back
  end

  it "shows a countdown warning before the session expires" do
    configure_session_timeout(
      expires_in: warning_offset_seconds + 120,
      warning_offset: warning_offset_seconds,
      duration: session_timeout_seconds
    )
    advance_session_time_by((warning_offset_seconds - 60).seconds)
    advance_session_time_by(60.seconds)
    show_warning_alert

    expect(page).to have_css(
      ".alert-warning",
      text: expected_warning_message(warning_offset_seconds)
    )
  end

  it "lets the user extend the session from the warning alert" do
    configure_session_timeout(
      expires_in: warning_offset_seconds + 5,
      warning_offset: warning_offset_seconds,
      duration: session_timeout_seconds
    )
    advance_session_time_by((warning_offset_seconds - 60).seconds)
    advance_session_time_by(60.seconds)
    show_warning_alert

    original_expiration = page.evaluate_script(session_timeout_expires_at_js)
    new_expiration = (Time.current + 10.minutes).to_i

    page.execute_script(<<~JS, new_expiration)
      (function(expiresAt) {
        const element = document.querySelector("#flash-messages");
        if (!window.StimulusApp || !element) return;
        const controllers = window.StimulusApp.controllers || [];
        let controller = controllers.find(function(controller) {
          return controller.element === element && controller.identifier === "session-timeout";
        });
        if (!controller && typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
          controller = window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout");
        }
        if (!controller) return;

        window.__keepaliveCalls = 0;
        window.__expectedExpiresAt = expiresAt;
        const keepaliveUrl = controller.keepaliveUrlValue;
        const originalFetch = window.fetch;
        let promiseResolver;
        let pendingPromise;

        window.fetch = (...args) => {
          const request = args[0];
          const url = typeof request === "string" ? request : request && request.url;
          const isKeepalive = url === keepaliveUrl;

          if (isKeepalive) {
            window.__keepaliveCalls += 1;
            if (window.__keepaliveCalls === 1) {
              return Promise.resolve({
                ok: true,
                json: () => Promise.resolve({ expires_at: expiresAt })
              });
            }
            if (pendingPromise) {
              return pendingPromise;
            }
            pendingPromise = new Promise((resolve) => {
              promiseResolver = resolve;
            });
            return pendingPromise;
          }

          return originalFetch ? originalFetch(...args) : Promise.resolve({ ok: true, json: () => Promise.resolve({}) });
        };

        window.__resolvePendingKeepalive = () => {
          if (promiseResolver) {
            promiseResolver({ ok: true, json: () => Promise.resolve({}) });
            promiseResolver = null;
            pendingPromise = null;
          }
        };
      })(arguments[0]);
    JS

    click_button I18n.t("session_timeout.stay_signed_in")

    page.execute_script("window.__resolvePendingKeepalive && window.__resolvePendingKeepalive()")

    expect(page).to have_no_css(".alert-warning")
    expect(page.evaluate_script("window.__keepaliveCalls")).to be >= 1
    controller_expires_at = page.evaluate_script(session_timeout_expires_at_js)
    expect(controller_expires_at).to be > original_expiration
    expect(controller_expires_at).to be_between(new_expiration, new_expiration + session_timeout_seconds).inclusive

    page.all("[data-session-timeout-signed-in]").each do |element|
      expect(element[:class].to_s).not_to include("d-none")
    end
    page.all("[data-session-timeout-signed-out]").each do |element|
      expect(element[:class].to_s).to include("d-none")
    end
  end

  it "displays an expiration alert and toggles navigation when the session lapses" do
    configure_session_timeout(
      expires_in: warning_offset_seconds + 300,
      warning_offset: warning_offset_seconds,
      duration: session_timeout_seconds
    )
    advance_session_time_by((warning_offset_seconds - 60).seconds)
    advance_session_time_by(60.seconds)
    advance_session_time_by(300.seconds)
    force_session_expiration

    expect(page).to have_no_css(".alert-warning")
    expect(page).to have_css(".alert-danger", text: I18n.t("session_timeout.expired_message"))

    page.all("[data-session-timeout-signed-in]").each do |element|
      expect(element[:class].to_s).to include("d-none")
    end
    page.all("[data-session-timeout-signed-out]").each do |element|
      expect(element[:class].to_s).not_to include("d-none")
    end
  end

  def expected_warning_message(seconds)
    I18n.t("session_timeout.warning_message", minutes: minutes_from_seconds(seconds))
  end

  def minutes_from_seconds(seconds)
    [ (seconds / 60.0).ceil, 1 ].max
  end

  def wait_for_session_timeout_controller
    page.find("#flash-messages", visible: :all)

    Timeout.timeout(15) do
      loop do
        controller_ready = page.evaluate_script(session_timeout_controller_present_js)
        break if controller_ready
        sleep 0.05
      end
    end
  end

  def wait_for_stimulus_application
    load_stimulus_library
    start_stimulus_application
    register_session_timeout_controller

    Timeout.timeout(15) do
      loop do
        ready = page.evaluate_script(session_timeout_controller_present_js)
        break if ready
        sleep 0.05
      end
    end
  rescue Timeout::Error
    raise "Stimulus application did not load"
  end

  def load_stimulus_library
    page.execute_script(<<~JS, stimulus_library_source)
      (function(source) {
        if (window.__stimulusLibraryLoaded) {
          window.StimulusLib = window.__stimulusLibraryReference || window.StimulusLib || window.Stimulus;
          return;
        }
        const script = document.createElement("script");
        script.type = "text/javascript";
        script.text = source;
        document.head.appendChild(script);
        window.__stimulusLibraryLoaded = true;
        window.__stimulusLibraryReference = window.Stimulus;
        window.StimulusLib = window.__stimulusLibraryReference;
      })(arguments[0]);
    JS
  end

  def start_stimulus_application
    page.execute_script(<<~JS)
      (function() {
        if (!window.__stimulusLibraryLoaded) return;
        if (!window.StimulusApp) {
          const library = window.StimulusLib || window.Stimulus;
          const application = library.Application.start();
          window.StimulusApp = application;
          window.Stimulus = application;
          window.__sessionTimeoutControllerRegistered = false;
        }
      })();
    JS
  end

  def register_session_timeout_controller
    page.execute_script(<<~JS, session_timeout_controller_source)
      (function(controllerFactorySource) {
        if (!window.StimulusApp || window.__sessionTimeoutControllerRegistered) return;
        const factory = new Function("Stimulus", controllerFactorySource);
        const ControllerClass = factory(window.StimulusLib || window.StimulusApp);
        window.StimulusApp.register("session-timeout", ControllerClass);
        window.__sessionTimeoutControllerRegistered = true;
      })(arguments[0]);
    JS
  end

  def show_warning_alert
    wait_for_session_timeout_controller
    visible = page.evaluate_script(<<~JS, warning_offset_seconds)
      (function(seconds) {
        const element = document.querySelector("#flash-messages");
        if (!window.StimulusApp || !element) return;
        const controllers = window.StimulusApp.controllers || [];
        let controller = controllers.find(function(controller) {
          return controller.element === element && controller.identifier === "session-timeout";
        });
        if (!controller && typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
          controller = window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout");
        }
        if (!controller) return false;
        if (typeof controller.hideWarning === "function") controller.hideWarning();
        controller.warningOffsetValue = seconds;
        controller.showWarning();
        return Boolean(controller.warningElement || document.querySelector("#flash-messages .alert-warning"));
      })(arguments[0]);
    JS
    raise "Unable to render session timeout warning" unless visible
  end

  def force_session_expiration
    wait_for_session_timeout_controller
    expired = page.evaluate_script(<<~JS)
      (function() {
        const element = document.querySelector("#flash-messages");
        if (!window.StimulusApp || !element) return;
        const controllers = window.StimulusApp.controllers || [];
        let controller = controllers.find(function(controller) {
          return controller.element === element && controller.identifier === "session-timeout";
        });
        if (!controller && typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
          controller = window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout");
        }
        if (!controller) return false;
        controller.handleExpiration();
        return Boolean(document.querySelector("#flash-messages .alert-danger"));
      })();
    JS
    raise "Unable to render session timeout expiration" unless expired
  end

  def stimulus_library_source
    @stimulus_library_source ||= Rails.root.join("node_modules/@hotwired/stimulus/dist/stimulus.umd.js").read
  end

  def session_timeout_controller_source
    @session_timeout_controller_source ||= begin
      source = Rails.root.join("app/javascript/controllers/session_timeout_controller.js").read
      source = source.each_line.reject { |line| line.strip.start_with?("import ") }.join
      source = source.sub("export default class extends Controller", "class SessionTimeoutController extends Stimulus.Controller")
      <<~JS
        return (function() {
          #{source}
          return SessionTimeoutController;
        })();
      JS
    end
  end

  def session_timeout_controller_present_js
    @session_timeout_controller_present_js ||= <<~JS
      (function() {
        if (!window.StimulusApp) return false;
        const element = document.querySelector("#flash-messages");
        if (!element) return false;
        const controllers = window.StimulusApp.controllers || [];
        if (controllers.some(function(controller) {
          return controller.element === element && controller.identifier === "session-timeout";
        })) {
          return true;
        }
        if (typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
          return Boolean(window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout"));
        }
        return false;
      })()
    JS
  end

  def session_timeout_expires_at_js
    @session_timeout_expires_at_js ||= <<~JS
      (function() {
        if (!window.StimulusApp) return null;
        const element = document.querySelector("#flash-messages");
        if (!element) return null;
        const controllers = window.StimulusApp.controllers || [];
        let controller = controllers.find(function(controller) {
          return controller.element === element && controller.identifier === "session-timeout";
        });
        if (!controller && typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
          controller = window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout");
        }
        return controller ? controller.expiresAtValue : null;
      })()
    JS
  end

  def configure_session_timeout(expires_in:, warning_offset:, duration: expires_in)
    now_seconds = Time.current.to_i
    Timeout.timeout(5) do
      loop do
        configured = page.evaluate_script(<<~JS, now_seconds, warning_offset, duration, expires_in)
          (function(now, warningOffset, duration, expiresIn) {
            const element = document.querySelector("#flash-messages");
            if (!window.StimulusApp || !element) return false;
            const controllers = window.StimulusApp.controllers || [];
            let controller = controllers.find(function(controller) {
              return controller.element === element && controller.identifier === "session-timeout";
            });
            if (!controller && typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
              controller = window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout");
            }
            if (!controller) return false;
            controller.warningOffsetValue = warningOffset;
            controller.durationValue = duration;
            controller.expiresAtValue = now + expiresIn;
            controller.resetTimers();
            return true;
          })(arguments[0], arguments[1], arguments[2], arguments[3]);
        JS
        break if configured
        sleep 0.05
      end
    end
  end

  def advance_session_time_by(duration)
    travel duration
    sync_client_clock
    recalculate_timers
  end

  def sync_client_clock
    now_ms = (Time.current.to_f * 1000).to_i
    page.execute_script(<<~JS, now_ms)
      (function(nowMs) {
        if (!window.__originalDateNow) {
          window.__originalDateNow = Date.now;
        }
        window.__testDateNow = nowMs;
        Date.now = () => window.__testDateNow;
      })(arguments[0]);
    JS
  end

  def recalculate_timers
    page.execute_script(<<~JS)
      (function() {
        const element = document.querySelector("#flash-messages");
        const controllers = window.StimulusApp.controllers || [];
        let controller = controllers.find(function(controller) {
          return controller.element === element && controller.identifier === "session-timeout";
        });
        if (!controller && typeof window.StimulusApp.getControllerForElementAndIdentifier === "function") {
          controller = window.StimulusApp.getControllerForElementAndIdentifier(element, "session-timeout");
        }
        controller && controller.resetTimers();
      })();
    JS
  end

  def restore_client_clock
    page.execute_script(<<~JS)
      if (window.__originalDateNow) {
        Date.now = window.__originalDateNow;
        delete window.__originalDateNow;
        delete window.__testDateNow;
      }
    JS
  rescue StandardError
    # Ignored - the browser may already be closed.
  end
end
