import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selectedAssetCount", "selectedFolderCount", "form", "folderForm", "assignForm", "assetIds", "folderIds", "assignAssetIds", "assignFolderIds"]

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
    const folderButton = document.getElementById("folder-batch-actions-btn")
    const assignButton = document.getElementById("assign-to-btn")
    
    const hasAssets = this.selectedAssets.size > 0
    const hasFolders = this.selectedFolders.size > 0
    const totalSelected = this.selectedAssets.size + this.selectedFolders.size
    
    // Show assign button if both assets and folders are selected
    if (hasAssets && hasFolders) {
      if (assignButton) {
        assignButton.style.display = "inline-block"
        // Update the count in the assign button
        const countSpan = assignButton.querySelector('.selection-count')
        if (countSpan) countSpan.textContent = totalSelected
      }
    } else {
      // Hide assign button when not needed
      if (assignButton) assignButton.style.display = "none"
    }
    
    // Show asset button if any assets are selected
    if (hasAssets) {
      if (assetButton) assetButton.style.display = "inline-block"
    } else {
      if (assetButton) assetButton.style.display = "none"
    }
    
    // Show folder button if any folders are selected
    if (hasFolders) {
      if (folderButton) folderButton.style.display = "inline-block"
    } else {
      if (folderButton) folderButton.style.display = "none"
    }
  }

  updateSelectedCount() {
    // Update asset count
    this.selectedAssetCountTargets.forEach(target => {
      target.textContent = this.selectedAssets.size
    })
    
    // Update folder count
    this.selectedFolderCountTargets.forEach(target => {
      target.textContent = this.selectedFolders.size
    })
  }

  openAssetModal() {
    if (this.selectedAssets.size === 0) {
      alert("Please select at least one asset")
      return
    }

    // Update the hidden field with selected asset IDs
    if (this.hasAssetIdsTarget) {
      this.assetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }

    // Reset form to "Unchanged" state
    this.resetAssetFormToUnchanged()

    // Show the asset modal
    const modal = new bootstrap.Modal(document.getElementById('assetBatchActionsModal'))
    modal.show()
  }

  openFolderModal() {
    if (this.selectedFolders.size === 0) {
      alert("Please select at least one folder")
      return
    }

    // Update the hidden field with selected folder IDs
    if (this.hasFolderIdsTarget) {
      this.folderIdsTarget.value = Array.from(this.selectedFolders).join(',')
    }

    // Reset form to "Unchanged" state
    this.resetFolderFormToUnchanged()

    // Show the folder modal
    const modal = new bootstrap.Modal(document.getElementById('folderBatchActionsModal'))
    modal.show()
  }

  openAssignModal() {
    if (this.selectedAssets.size === 0 && this.selectedFolders.size === 0) {
      alert("Please select at least one item")
      return
    }

    // Update the hidden fields with selected IDs for the assign form
    if (this.hasAssignAssetIdsTarget) {
      this.assignAssetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }
    if (this.hasAssignFolderIdsTarget) {
      this.assignFolderIdsTarget.value = Array.from(this.selectedFolders).join(',')
    }

    // Update the counts in the modal
    const folderCountBadge = document.getElementById('assign-folder-count')
    const assetCountBadge = document.getElementById('assign-asset-count')
    if (folderCountBadge) {
      folderCountBadge.textContent = `${this.selectedFolders.size} folder${this.selectedFolders.size !== 1 ? 's' : ''}`
    }
    if (assetCountBadge) {
      assetCountBadge.textContent = `${this.selectedAssets.size} asset${this.selectedAssets.size !== 1 ? 's' : ''}`
    }

    // Reset form
    this.resetAssignFormToUnchanged()

    // Show the assign modal
    const modal = new bootstrap.Modal(document.getElementById('assignToModal'))
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
  }

  resetFolderFormToUnchanged() {
    const modal = document.getElementById('folderBatchActionsModal')
    
    // Reset all select dropdowns to empty value (which shows "Unchanged")
    modal.querySelectorAll('select').forEach(select => {
      select.value = ''
    })
  }

  resetAssignFormToUnchanged() {
    const modal = document.getElementById('assignToModal')
    
    // Reset select dropdown to prompt state
    const select = modal.querySelector('select[name*="assigned_user_id"]')
    if (select) {
      select.selectedIndex = 0 // Reset to prompt
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

  submitFolderBatchAction(event) {
    // Update hidden fields with current selection before submitting
    if (this.hasFolderIdsTarget) {
      this.folderIdsTarget.value = Array.from(this.selectedFolders).join(',')
    }
    
    // Let the form submit naturally with Turbo handling the response
    // The form already has the correct action and method
  }

  submitAssignAction(event) {
    // Update hidden fields with current selection before submitting
    if (this.hasAssignAssetIdsTarget) {
      this.assignAssetIdsTarget.value = Array.from(this.selectedAssets).join(',')
    }
    if (this.hasAssignFolderIdsTarget) {
      this.assignFolderIdsTarget.value = Array.from(this.selectedFolders).join(',')
    }
    
    // Let the form submit naturally with Turbo handling the response
    // The form already has the correct action and method
  }

  handleFormSubmitEnd(event) {
    // Check if this is our batch actions form and if it was successful
    if ((event.target.classList.contains('batch-actions-form') || 
         event.target.classList.contains('folder-batch-actions-form') ||
         event.target.classList.contains('assign-to-form')) && 
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
    
    // Close folder modal
    const folderModal = bootstrap.Modal.getInstance(document.getElementById('folderBatchActionsModal'))
    if (folderModal) {
      folderModal.hide()
    }
    
    // Close assign modal
    const assignModal = bootstrap.Modal.getInstance(document.getElementById('assignToModal'))
    if (assignModal) {
      assignModal.hide()
    }
  }

  clearSelection() {
    this.selectedAssets.clear()
    this.selectedFolders.clear()
    this.updateButtonVisibility()
    this.updateSelectedCount()
  }
}