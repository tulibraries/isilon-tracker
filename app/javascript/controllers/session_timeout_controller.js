import { Controller } from "@hotwired/stimulus";

// Manages Devise session timeout warnings and keepalive behavior.
export default class extends Controller {
  static values = {
    expiresAt: Number,
    duration: Number,
    warningOffset: Number,
    keepaliveUrl: String,
    flashContainer: String,
  };

  connect() {
    this.flashElement = document.getElementById(this.flashContainerValue);
    if (!this.flashElement) return;

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

    if (!this.hasKeepaliveUrlValue) return;

    fetch(this.keepaliveUrlValue, {
      method: "POST",
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Accept": "application/json",
      },
      credentials: "same-origin",
    })
      .then((response) => {
        if (!response.ok) throw new Error("Keepalive request failed");

        if (this.hasDurationValue) {
          this.expiresAtValue = Math.floor(Date.now() / 1000) + this.durationValue;
        }

        this.hideWarning();
        this.resetTimers();
      })
      .catch(() => this.showError());
  }

  showWarning() {
    if (!this.flashElement || this.warningVisible) return;

    const alert = document.createElement("div");
    alert.className = "alert alert-warning fade show mt-3";
    alert.setAttribute("role", "alert");
    alert.innerHTML = `
      <div class="d-flex flex-column flex-sm-row align-items-sm-center justify-content-between gap-2">
        <span>Your session will expire in ${this.warningOffsetValue} seconds.</span>
        <button type="button" class="btn btn-sm btn-primary" data-action="session-timeout#resetSession">
          Stay signed in
        </button>
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

    const alert = document.createElement("div");
    alert.className = "alert alert-danger fade show mt-3";
    alert.setAttribute("role", "alert");
    alert.textContent = "We couldn't extend your session. Please save your work and sign in again.";

    this.flashElement.prepend(alert);
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
