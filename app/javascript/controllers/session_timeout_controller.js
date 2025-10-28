import { Controller } from "@hotwired/stimulus";

// Manages Devise session timeout warnings and keepalive behavior.
export default class extends Controller {
  static values = {
    expiresAt: Number,
    duration: Number,
    warningOffset: Number,
    keepaliveUrl: String,
    warningMessage: String,
    staySignedInLabel: String,
    errorMessage: String,
    expiredMessage: String,
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
    const expirationAt = this.expiresAtValue * 1000;
    const millisUntilWarning = warningAt - Date.now();
    const millisUntilExpiration = expirationAt - Date.now();

    if (millisUntilWarning <= 0) {
      this.showWarning();
    } else {
      this.warningTimer = setTimeout(() => this.showWarning(), millisUntilWarning);
    }

    if (millisUntilExpiration <= 0) {
      this.handleExpiration();
    } else {
      this.expirationTimer = setTimeout(() => this.handleExpiration(), millisUntilExpiration);
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

  showWarning() {
    if (!this.flashElement || this.warningVisible) return;

    const messageTemplate = this.valueOrDefault("warningMessage", "Your session will expire in %{seconds} seconds.");
    const messageText = messageTemplate.replace("%{seconds}", this.warningOffsetValue);
    const staySignedInLabel = this.valueOrDefault("staySignedInLabel", "Stay signed in");

    const alert = document.createElement("div");
    alert.className = "alert alert-warning alert-dismissible fade show mt-3";
    alert.setAttribute("role", "alert");
    alert.innerHTML = `
      <div class="d-flex flex-column flex-sm-row align-items-sm-center justify-content-between gap-2">
        <span>${messageText}</span>
        <div class="d-flex gap-2">
          <button type="button" class="btn btn-sm btn-primary" data-action="click->session-timeout#resetSession">
            ${staySignedInLabel}
          </button>
        </div>
      </div>
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
    this.hideWarning();
    this.showAlert({
      level: "danger",
      message: this.valueOrDefault("errorMessage", "We couldn't extend your session. Please save your work and sign in again."),
    });
  }

  clearTimers() {
    if (this.warningTimer) {
      clearTimeout(this.warningTimer);
      this.warningTimer = null;
    }
    if (this.expirationTimer) {
      clearTimeout(this.expirationTimer);
      this.expirationTimer = null;
    }
  }

  get csrfToken() {
    const element = document.querySelector("meta[name='csrf-token']");
    return element && element.getAttribute("content");
  }

  handleExpiration() {
    this.clearTimers();
    this.hideWarning();
    if (!this.flashElement) return;

    this.showAlert({
      level: "danger",
      message: this.valueOrDefault("expiredMessage", "Your session has expired. Please sign in again to continue."),
      trackWarning: true,
    });
  }

  showAlert({ level, message, trackWarning = false }) {
    const alert = document.createElement("div");
    alert.className = `alert alert-${level} alert-dismissible fade show mt-3`;
    alert.setAttribute("role", "alert");
    alert.innerHTML = `
      <span>${message}</span>
      <button type="button" class="btn-close" data-action="click->session-timeout#hideAlert" aria-label="Close"></button>
    `;

    this.flashElement.prepend(alert);

    if (trackWarning) {
      this.warningElement = alert;
      this.warningVisible = true;
    }
  }

  hideAlert(event) {
    event.preventDefault();
    this.hideWarning();
  }

  valueOrDefault(name, fallback = "") {
    const hasKey = this[`has${this.capitalize(name)}Value`];
    if (hasKey) {
      return this[`${name}Value`];
    }
    return fallback;
  }

  capitalize(value) {
    return value.charAt(0).toUpperCase() + value.slice(1);
  }
}
