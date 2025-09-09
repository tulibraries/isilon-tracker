import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectedCount", "form", "assetIds"]

  connect() {
    console.log("Batch Actions controller connected")
    this.selectedAssets = new Set()
    this.updateButtonVisibility()
    
    // Listen for tree selection changes from wunderbaum controller
    document.addEventListener("wunderbaum:selectionChanged", this.handleSelectionChange.bind(this))
    
    // Listen for turbo:submit-end to close modal after successful submission
    document.addEventListener("turbo:submit-end", this.handleFormSubmitEnd.bind(this))
  }

  disconnect() {
    document.removeEventListener("wunderbaum:selectionChanged", this.handleSelectionChange.bind(this))
    document.removeEventListener("turbo:submit-end", this.handleFormSubmitEnd.bind(this))
  }

  handleSelectionChange(event) {
    this.selectedAssets = new Set(event.detail.selectedAssetIds)
    this.updateButtonVisibility()
    this.updateSelectedCount()
  }

  updateButtonVisibility() {
    const button = document.getElementById("batch-actions-btn")
    if (this.selectedAssets.size > 0) {
      button.style.display = "inline-block"
    } else {
      button.style.display = "none"
    }
  }

  updateSelectedCount() {
    this.selectedCountTargets.forEach(target => {
      target.textContent = this.selectedAssets.size
    })
  }

  openModal() {
    console.log("Opening batch actions modal")
    if (this.selectedAssets.size === 0) {
      alert("Please select at least one asset")
      return
    }

    // Update the hidden field with selected asset IDs
    if (this.hasAssetIdsTarget) {
      this.assetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }

    // Reset all form fields to "Unchanged" state
    this.resetFormToUnchanged()

    // Show the modal
    const modal = new bootstrap.Modal(document.getElementById('batchActionsModal'))
    modal.show()
  }

  resetFormToUnchanged() {
    const modal = document.getElementById('batchActionsModal')
    
    // Reset all select dropdowns to empty value (which shows "Unchanged")
    modal.querySelectorAll('select').forEach(select => {
      select.value = ''
    })
    
    // Reset radio buttons to the "Unchanged" option
    const unchangedRadio = modal.querySelector('input[name*="aspace_linking_status"][value=""]')
    if (unchangedRadio) {
      unchangedRadio.checked = true
    }
  }

  submitBatchAction(event) {
    // Update hidden field with current selection before submitting
    if (this.hasAssetIdsTarget) {
      this.assetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }
    
    // Let the form submit naturally with Turbo handling the response
    // The form already has the correct action and method
  }

  handleFormSubmitEnd(event) {
    // Check if this is our batch actions form and if it was successful
    if (event.target.classList.contains('batch-actions-form') && event.detail.success) {
      const updatedAssetIds = Array.from(this.selectedAssets)
      this.closeModal()
      this.refreshWunderbaumTree(updatedAssetIds)
    }
  }

  refreshWunderbaumTree(updatedAssetIds = []) {
    // Find the wunderbaum controller and trigger a refresh
    const wunderbaumElement = document.querySelector('[data-controller*="wunderbaum"]')
    
    if (wunderbaumElement) {
      const wunderbaumController = this.application.getControllerForElementAndIdentifier(wunderbaumElement, 'wunderbaum')
      
      if (wunderbaumController && wunderbaumController.refreshTreeDisplay) {
        wunderbaumController.refreshTreeDisplay(updatedAssetIds)
      }
    }
  }

  closeModal() {
    const modal = bootstrap.Modal.getInstance(document.getElementById('batchActionsModal'))
    if (modal) {
      modal.hide()
    }
  }

  clearSelection() {
    this.selectedAssets.clear()
    this.updateButtonVisibility()
    this.updateSelectedCount()
  }
}