import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectedAssetCount", "form", "assetIds", "folderIds"]

  connect() {
    this.selectedAssets = new Set()
    this.selectedFolders = new Set()
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
    this.selectedFolders = new Set(event.detail.selectedFolderIds || [])
    this.updateButtonVisibility()
    this.updateSelectedCount()
  }

  updateButtonVisibility() {
    const assetButton = document.getElementById("asset-batch-actions-btn")
    
    const hasAssets = this.selectedAssets.size > 0
    const hasFolders = this.selectedFolders.size > 0
    const totalSelected = this.selectedAssets.size + this.selectedFolders.size
    
    // Show batch actions button if any assets or folders are selected
    if (totalSelected > 0) {
      if (assetButton) assetButton.style.display = "inline-block"
    } else {
      if (assetButton) assetButton.style.display = "none"
    }
  }

  updateSelectedCount() {
    // Update total count (assets + folders)
    const totalCount = this.selectedAssets.size + this.selectedFolders.size
    this.selectedAssetCountTargets.forEach(target => {
      target.textContent = totalCount
    })
  }

  openAssetModal() {
    const totalSelected = this.selectedAssets.size + this.selectedFolders.size
    if (totalSelected === 0) {
      this.showFlashMessage("Please select at least one item", "warning")
      return
    }

    // Update the hidden fields with selected IDs
    if (this.hasAssetIdsTarget) {
      this.assetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }
    
    // Update folder IDs field (create it if it doesn't exist)
    let folderIdsInput = document.querySelector('#assetBatchActionsModal input[name="folder_ids"]')
    if (!folderIdsInput) {
      folderIdsInput = document.createElement('input')
      folderIdsInput.type = 'hidden'
      folderIdsInput.name = 'folder_ids'
      document.querySelector('#assetBatchActionsModal form').appendChild(folderIdsInput)
    }
    folderIdsInput.value = Array.from(this.selectedFolders).join(',')

    // Reset form to "Unchanged" state
    this.resetAssetFormToUnchanged()

    // Show the modal
    const modal = new bootstrap.Modal(document.getElementById('assetBatchActionsModal'))
    modal.show()
  }

  resetAssetFormToUnchanged() {
    const modal = document.getElementById('assetBatchActionsModal')
    
    // Reset all select dropdowns to empty value (which shows "Unchanged")
    modal.querySelectorAll('select').forEach(select => {
      select.value = ''
    })
    
    // Reset radio buttons to the "Unchanged" option
    const unchangedRadio = modal.querySelector('input[name*="aspace_linking_status"][value=""]')
    if (unchangedRadio) {
      unchangedRadio.checked = true
    }

    const notesInput = modal.querySelector('input[name="notes"]')
    if (notesInput) {
      notesInput.value = ''
    }
  }

  submitBatchAction(event) {
    // Update hidden fields with current selection before submitting
    if (this.hasAssetIdsTarget) {
      this.assetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }
    
    // Let the form submit naturally with Turbo handling the response
    // The form already has the correct action and method
  }

  handleFormSubmitEnd(event) {
    // Check if this is our batch actions form and if it was successful
    if (event.target.classList.contains('batch-actions-form') && 
        event.detail.success) {
      const updatedAssetIds = Array.from(this.selectedAssets)
      const updatedFolderIds = Array.from(this.selectedFolders)
      this.closeModals()
      this.refreshWunderbaumTree(updatedAssetIds, updatedFolderIds)
    }
  }

  refreshWunderbaumTree(updatedAssetIds = [], updatedFolderIds = []) {
    // Find the wunderbaum controller and trigger a refresh
    const wunderbaumElement = document.querySelector('[data-controller*="wunderbaum"]')
    
    if (wunderbaumElement) {
      const wunderbaumController = this.application.getControllerForElementAndIdentifier(wunderbaumElement, 'wunderbaum')
      
      if (wunderbaumController && wunderbaumController.refreshTreeDisplay) {
        wunderbaumController.refreshTreeDisplay(updatedAssetIds, updatedFolderIds)
      }
    }
  }

  closeModals() {
    // Close asset modal
    const assetModal = bootstrap.Modal.getInstance(document.getElementById('assetBatchActionsModal'))
    if (assetModal) {
      assetModal.hide()
    }
  }

  clearSelection() {
    this.selectedAssets.clear()
    this.selectedFolders.clear()
    this.updateButtonVisibility()
    this.updateSelectedCount()
  }

  showFlashMessage(message, type) {
    // Create a temporary flash message element
    const flashContainer = document.getElementById("flash-messages")
    if (flashContainer) {
      flashContainer.innerHTML = `
        <div class="alert alert-${type} alert-dismissible fade show" role="alert">
          ${message}
          <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
        </div>
      `
    }
  }
}
