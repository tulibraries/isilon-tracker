import { Controller } from "@hotwired/stimulus";

// Manages Devise session timeout warnings and keepalive behavior.
export default class extends Controller {
  static values = {
    expiresAt: Number,
    duration: Number,
    warningOffset: Number,
    keepaliveUrl: String,
  };

  connect() {
    this.flashElement = this.element;
    if (!this.flashElement) return;
    this.requestInFlight = false;

    this.resetTimers();
  }

  disconnect() {
    this.clearTimers();
    this.hideWarning();
  }

  resetTimers() {
    this.clearTimers();

    if (!this.hasExpiresAtValue || !this.hasWarningOffsetValue) return;

    const warningAt = (this.expiresAtValue - this.warningOffsetValue) * 1000;
    const millisUntilWarning = warningAt - Date.now();

    if (millisUntilWarning <= 0) {
      this.showWarning();
    } else {
      this.warningTimer = setTimeout(() => this.showWarning(), millisUntilWarning);
    }
  }

  resetSession(event) {
    event.preventDefault();
    if (!this.hasKeepaliveUrlValue || this.requestInFlight) return;
    this.requestInFlight = true;

    fetch(this.keepaliveUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Accept": "application/json",
        "Content-Type": "application/json",
      },
      credentials: "same-origin",
    })
      .then((response) => {
        if (!response.ok) throw new Error("Keepalive request failed");
        return response.json().catch(() => ({}));
      })
      .then((data) => {
        if (data.expires_at) {
          this.expiresAtValue = data.expires_at;
        } else if (this.hasDurationValue) {
          this.expiresAtValue = Math.floor(Date.now() / 1000) + this.durationValue;
        }
        this.hideWarning();
        this.resetTimers();
      })
      .catch(() => this.showError())
      .finally(() => {
        this.requestInFlight = false;
      });
  }

  dismissWarning(event) {
    event.preventDefault();
    this.hideWarning();
  }

  showWarning() {
    if (!this.flashElement || this.warningVisible) return;

    const alert = document.createElement("div");
    alert.className = "alert alert-warning alert-dismissible fade show mt-3";
    alert.setAttribute("role", "alert");
    alert.innerHTML = `
      <div class="d-flex flex-column flex-sm-row align-items-sm-center justify-content-between gap-2">
        <span>Your session will expire in ${this.warningOffsetValue} seconds.</span>
        <div class="d-flex gap-2">
          <button type="button" class="btn btn-sm btn-primary" data-action="click->session-timeout#resetSession">
            Stay signed in
          </button>
          <button type="button" class="btn btn-sm btn-outline-secondary" data-action="click->session-timeout#dismissWarning">
            Dismiss
          </button>
        </div>
      </div>
      <button type="button" class="btn-close" data-action="click->session-timeout#dismissWarning" aria-label="Close"></button>
    `;

    this.flashElement.prepend(alert);
    this.warningElement = alert;
    this.warningVisible = true;
  }

  hideWarning() {
    if (!this.warningVisible || !this.warningElement) return;
    this.warningElement.remove();
    this.warningElement = null;
    this.warningVisible = false;
  }

  showError() {
    if (!this.flashElement) return;

    const alert = document.createElement("div");
    alert.className = "alert alert-danger fade show mt-3";
    alert.setAttribute("role", "alert");
    alert.textContent = "We couldn't extend your session. Please save your work and sign in again.";

    this.flashElement.prepend(alert);
    this.hideWarning();
  }

  clearTimers() {
    if (this.warningTimer) {
      clearTimeout(this.warningTimer);
      this.warningTimer = null;
    }
  }

  get csrfToken() {
    const element = document.querySelector("meta[name='csrf-token']");
    return element && element.getAttribute("content");
  }
}
