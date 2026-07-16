import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "modeButton"]

  connect() {
    this.lastSignature = null
    this.debounceTimer = null
    this.boundFiltersChanged = this.filtersChanged.bind(this)

    document.addEventListener("wunderbaum:filtersChanged", this.boundFiltersChanged)
    this.syncModeButton()
  }

  disconnect() {
    document.removeEventListener("wunderbaum:filtersChanged", this.boundFiltersChanged)
    this.clearDebounce()
  }

  inputChanged() {
    this.clearDebounce()
    this.debounceTimer = window.setTimeout(() => {
      this.requestFilter()
    }, 250)
  }

  keyDown(event) {
    if (event.key !== "Escape") return
    event.preventDefault()
    this.clearFilters()
  }

  filtersChanged() {
    this.requestFilter({ force: true })
  }

  async clearFilters() {
    if (this.hasInputTarget) {
      this.inputTarget.value = ""
    }

    this.lastSignature = null
    this.clearDebounce()

    const wunderbaum = this.wunderbaumController()
    if (!wunderbaum) return

    await wunderbaum.clearAllFilters()
    this.syncModeButton()
  }

  async toggleMode() {
    const wunderbaum = this.wunderbaumController()
    if (!wunderbaum) {
      this.syncModeButton()
      return
    }

    const mode = wunderbaum.toggleFilterMode()

    if (this.hasInputTarget) {
      const raw = this.inputTarget.value
      const request = wunderbaum.getFilterRequestParams(raw)
      const signature = request.params?.toString() || null

      if (!request.empty) {
        if (mode === "dim") {
          await wunderbaum.applyDimFilter(raw, signature)
        } else {
          if (!(await wunderbaum.applyCachedHideFilter?.(signature))) {
            await this.requestFilter({ force: true })
          } else {
            wunderbaum.prefetchDimFilter?.(raw, signature)
          }
        }
      }
    }

    this.syncModeButton()
  }

  async requestFilter({ force = false } = {}) {
    const wunderbaum = this.wunderbaumController()
    if (!wunderbaum) return

    const raw = this.hasInputTarget ? this.inputTarget.value : ""
    const request = wunderbaum.getFilterRequestParams(raw)

    if (request.empty) {
      this.lastSignature = null
      await wunderbaum.clearAllFilters()
      this.syncModeButton()
      return
    }

    const signature = request.params.toString()
    if (!force && signature === this.lastSignature) {
      return
    }

    if (wunderbaum.getFilterMode?.() === "dim") {
      this.lastSignature = signature
      await wunderbaum.applyDimFilter(raw, signature)
      this.syncModeButton()
      return
    }

    this.lastSignature = signature

    if (wunderbaum.hasCachedHideFilter?.(signature)) {
      await wunderbaum.applyCachedHideFilter(signature)
      wunderbaum.prefetchDimFilter?.(raw, signature)
      this.syncModeButton()
      return
    }

    const built = wunderbaum.buildFilterRequest(raw)
    if (built.empty) {
      this.syncModeButton()
      return
    }

    try {
      const response = await fetch(
        `/volumes/${wunderbaum.volumeIdValue}/file_tree_filter_results.json?${built.params.toString()}`,
        {
          headers: { Accept: "application/json" },
          credentials: "same-origin"
        }
      )

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const payload = await response.json()
      wunderbaum.cacheHideFilterResults?.(built.signature, payload)
      await wunderbaum.applyFilterResults(payload, built.seq)
      wunderbaum.prefetchDimFilter?.(raw, built.signature)
    } catch (error) {
      console.error("Failed to fetch filtered tree results", error)
      await wunderbaum._abortPendingHideFilter?.(built.seq)
    } finally {
      wunderbaum.finalizeFilterRequest(built.seq)
      this.syncModeButton()
    }
  }

  syncModeButton() {
    if (!this.hasModeButtonTarget) return

    const wunderbaum = this.wunderbaumController()
    const mode = wunderbaum?.getFilterMode?.() || "hide"
    const icon = this.modeButtonTarget.querySelector("i")
    const isHideMode = mode === "hide"

    this.modeButtonTarget.classList.toggle("active", isHideMode)
    this.modeButtonTarget.disabled = false
    this.modeButtonTarget.setAttribute(
      "title",
      isHideMode ? "Hide unmatched nodes" : "Dim unmatched nodes"
    )
    this.modeButtonTarget.setAttribute(
      "aria-pressed",
      isHideMode ? "true" : "false"
    )

    if (icon) {
      icon.classList.remove("bi-filter-square", "bi-filter-square-fill")
      icon.classList.add(isHideMode ? "bi-filter-square-fill" : "bi-filter-square")
    }
  }

  clearDebounce() {
    if (this.debounceTimer) {
      window.clearTimeout(this.debounceTimer)
      this.debounceTimer = null
    }
  }

  wunderbaumController() {
    const element = document.querySelector('[data-controller*="wunderbaum"]')
    if (!element) return null

    return this.application.getControllerForElementAndIdentifier(element, "wunderbaum")
  }
}
