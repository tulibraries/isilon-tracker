import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, volumeId: Number };

  columnFilters = new Map();
  columnValueCache = new Map();
  assetsLoadedFor = new Set();
  expandingNodes = new Set();
  currentFilterPredicate = null;
  currentFilterOpts = null;
  currentQuery = "";
  filterMode = "hide";
  folderCache = new Map();
  assetCache = new Map();
  loadedFolders = new Set();

  inflightControllers = new Set();
  _filterTimer = null;
  _filterSeq = 0;

  async connect() {
    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      const source = await res.json();
      this._isScrollDrivenExpansion = false;

      this.tree = new Wunderbaum({
        element: this.element,
        id: "tree",
        keyboard: true,
        autoActivate: true,
        checkbox: true,
        lazy: true,
        selectMode: "hier",
        columnsResizable: true,
        fixedCol: true,

        filter: {
          autoApply: true,
          autoExpand: false,
          matchBranch: false,
          fuzzy: false,
          hideExpanders: false,
          highlight: false,
          leavesOnly: false,
          mode: this.filterMode,
          noData: true,
          menu: true
        },

        columns: [
          { id: "*", title: "Filename", width: "500px" },
          {
            id: "migration_status",
            classes: "wb-helper-center",
            filterable: true,
            title: "Migration status",
            width: "150px",
            html: `<select></select>`
          },
          {
            id: "assigned_to",
            classes: "wb-helper-center",
            filterable: true,
            title: "Assigned To",
            width: "150px",
            html: `<select></select>`
          },
          {
            id: "notes",
            classes: "wb-helper-center",
            title: "Notes",
            width: "500px",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id: "file_type",
            classes: "wb-helper-center",
            title: "File type",
            width: "150px"
          },
          { id: "file_size", classes: "wb-helper-center", title: "File size", width: "150px" },
          { id: "isilon_date", classes: "wb-helper-center", title: "Isilon date created", width: "150px" },
          {
            id: "contentdm_collection_id",
            classes: "wb-helper-center",
            filterable: true,
            title: "Contentdm Collection",
            width: "150px",
            html: `<select></select>`
          },
          {
            id: "aspace_collection_id",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace Collection",
            width: "150px",
            html: `<select></select>`
          },
          {
            id: "preservica_reference_id",
            classes: "wb-helper-center",
            title: "Preservica Reference",
            width: "150px",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id: "aspace_linking_status",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace linking status",
            width: "150px",
            html: `<input type="checkbox" tabindex="-1">`
          },
        ],

        icon: ({ node }) => {
          if (!node.data.folder) return "bi bi-files";
        },

        lazyLoad: (e) => {
          if (!e.node?.data?.folder) return [];
          const id = e.node.data.key ?? e.node.data.id;
          return {
            url: `/volumes/${this.volumeIdValue}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(String(id))}`,
            options: { headers: { Accept: "application/json" }, credentials: "same-origin" }
          };
        },

        expand: async (e) => {
          const node = e.node;
          if (!node?.data?.folder) return;

          const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id);

          if (this.expandingNodes.has(nodeKey)) {
            return;
          }

          await this._ensureAssetsForFolderCancellable(
            nodeKey,
            this._filterSeq
          );

          if (!this._isScrollDrivenExpansion) {
            this._reapplyFilterIfAny();
          }
        },

        postProcess: (e) => { e.result = e.response; },

        renderHeaderCell: (e) => {
          const { colDef, cellElem } = e.info;
          cellElem.dataset.colid = colDef.id;
          this._setFilterIconState(colDef.id, colDef.filterActive);
        },

        render: (e) => {
          const util = e.util;
          const node = e.node;
          const isFolder = e.node.data.folder === true;

          for (const colInfo of Object.values(e.renderColInfosById)) {
            const colId = colInfo.id;
            const value = node.data[colId];

            if (value != null && value !== "") {
              let set = this.columnValueCache.get(colId);
              if (!set) {
                set = new Set();
                this.columnValueCache.set(colId, set);
              }
              set.add(String(value));
            }

            util.setValueToElem(colInfo.elem, value ?? "");
          }

          const titleElem = e.nodeElem.querySelector("span.wb-title");
          if (!titleElem) return;

          if (isFolder) {
            titleElem.textContent = node.title || "";
          } else {
            titleElem.innerHTML =
              `<a href="${node.data.url}" class="asset-link" data-turbo="false">${node.title}</a>`;
          }
        },
        
        buttonClick: (e) => {
          if (e.command === "filter") {
            const colId = e.info.colDef.id;
            const colIdx = e.info.colIdx;
            const allCols = this.element.querySelectorAll(".wb-header .wb-col");
            const colCell = allCols[colIdx];
            if (!colCell) return;
            const icon = colCell.querySelector("[data-command='filter']");
            if (!icon) return;
            this._showDropdownFilter(icon, colId, colIdx);
          }
        },

        change: (e) => {
          const util = e.util;
          const colId = e.info.colId;
          const value = util.getValueFromElem(e.inputElem, true);

          e.node.data[colId] = value;
          this._saveCellChange(e.node, colId, value);
        },

        select: (e) => {
          this._emitSelectionChange();
        },

        source
      });
    

      this._fetchOptions("/migration_statuses.json", "migrationStatusOptions", "migration_status");
      this._fetchOptions("/aspace_collections.json", "aspaceCollectionOptions", "aspace_collection_id");
      this._fetchOptions("/contentdm_collections.json", "contentdmCollectionOptions", "contentdm_collection_id");
      this._fetchOptions("/users.json", "userOptions", "assigned_to");

      this._setupInlineFilter();
      this._setupClearFiltersButton();
      this._setupFilterModeToggle();

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);    }
  }

  disconnect() {
    clearTimeout(this._filterTimer);
    this._cancelInflight();
  }

  _setupInlineFilter() {
    const input = document.getElementById("tree-filter");
    if (!input) return;

    input.addEventListener("input", () => {
      clearTimeout(this._filterTimer);
      this._filterTimer = setTimeout(() => this._runDeepFilter(input.value || ""), 300);
    });

    input.addEventListener("keydown", (e) => {
      
      if (e.key === "Escape") {
        input.value = "";
        this._runDeepFilter("");
      }
    });
  }

  _setupClearFiltersButton() {
    const btn = document.getElementById("clear-filters");
    if (!btn) return;

    btn.addEventListener("click", () => {
      const input = document.getElementById("tree-filter");
      if (input) input.value = "";

      this.columnFilters.clear();
      this.currentFilterPredicate = null;
      this.currentFilterOpts = null;
      this.currentQuery = "";
      this.filterMode = "dim";
      this.loadedFolders.clear();
      if (this.tree?.columns) {
        this.tree.columns.forEach((col) => {
          col.filterActive = false;
          this._setFilterIconState(col.id, false);
        });
      }

      document.querySelectorAll(".wb-popup").forEach((el) => el.remove());

      this.element.querySelectorAll(".wb-header select").forEach((select) => {
        if (select.options.length > 0) select.selectedIndex = 0;
      });

      if (this.tree?.root) {
        this.tree.root.visit((node) => {
          if (node.expanded) {
            node.setExpanded(false);
          }
        });
      }

      this.tree.clearFilter();
      this.columnValueCache.clear();
      this._setLoading(false);
      this._updateFilterModeButton();
    });
  }

  async _runDeepFilter(raw) {
    this._cancelInflight();
    const mySeq = ++this._filterSeq;
    this.loadedFolders.clear();

    const q = (raw || "").trim().toLowerCase();
    this.currentQuery = q;
    const hasColumnFilters = this.columnFilters.size > 0;

    if (!q && !hasColumnFilters) {
      this.currentFilterPredicate = null;
      this.currentFilterOpts = null;
      this.tree.clearFilter();
      this._collapseFilterExpansions();
      this._setLoading(false);
      this._updateFilterModeButton();
      return;
    }

    this._setLoading(true, "Searching…");

    const params = new URLSearchParams();
    if (q) params.set("q", q);
    for (const [col, val] of this.columnFilters.entries()) {
      if (val !== "") params.set(col, val);
    }

    const searchCtrl = this._beginFetchGroup();
    let folders = [], assets = [];
    try {
      [folders, assets] = await Promise.all([
        this._fetchJson(`/volumes/${this.volumeIdValue}/file_tree_folders_search.json?${params.toString()}`, searchCtrl).catch(() => []),
        this._fetchJson(`/volumes/${this.volumeIdValue}/file_tree_assets_search.json?${params.toString()}`, searchCtrl).catch(() => []),
      ]);
    } finally {
      this.inflightControllers.delete(searchCtrl);
    }
    if (mySeq !== this._filterSeq) return;

    await this._materializeSearchResults(folders, assets, mySeq);

    this._applyPredicate(q);
    this._setLoading(false);
  }

  _applyPredicate(q) {
    const predicate = (node) => {
      if (q) {
      const text =
          String(
            node.data.title ??
            node.data.name ??
            node.title ??
            ""
          ).toLowerCase();

        if (!text.includes(q)) return false;
      }

      for (const [colId, val] of this.columnFilters.entries()) {
        const nv = node.data[colId];
        if (nv == null || String(nv).toLowerCase() !== String(val).toLowerCase()) return false;
      }
      return true;
    };
    const opts = { leavesOnly: false, matchBranch: false, mode: this.filterMode };
    this.currentFilterPredicate = predicate;
    this.currentFilterOpts = opts;
    this.tree.filterNodes(predicate, opts);
    this._updateFilterModeButton();
  }

  _reapplyFilterIfAny() {
    if (this.currentFilterPredicate) {
      const opts = { ...(this.currentFilterOpts || {}), mode: this.filterMode };
      this.currentFilterOpts = opts;
      this.tree.filterNodes(this.currentFilterPredicate, opts);
    }
    this._updateFilterModeButton();
  }

  _findNodeByKey(key) {
    const skey = String(key);
    return this.tree?.findKey?.(skey) ?? null;
  }

  _setupFilterModeToggle() {
    const btn = document.getElementById("filter-mode-toggle");
    if (!btn) return;

    btn.addEventListener("click", () => {
      if (btn.disabled) return;
      this.filterMode = this.filterMode === "hide" ? "dim" : "hide";
      if (this.tree?.options?.filter) {
        this.tree.options.filter.mode = this.filterMode;
      }
      if (this.currentFilterOpts) {
        this.currentFilterOpts.mode = this.filterMode;
      }
      this._reapplyFilterIfAny();
    });

    this._updateFilterModeButton();
  }

  _updateFilterModeButton() {
    const btn = document.getElementById("filter-mode-toggle");
    if (!btn) return;
    const icon = btn.querySelector("i");
    const isHideMode = this.filterMode === "hide";

    btn.classList.toggle("active", isHideMode);
    btn.setAttribute("title", isHideMode ? "Hide unmatched nodes" : "Dim unmatched nodes");

    if (icon) {
      icon.classList.remove("bi-filter-square", "bi-filter-square-fill");
        icon.classList.add("bi-filter-square");
    }
  }

  _setFilterIconState(colId, active) {
    if (!colId) return;
    const icon = this.element?.querySelector(`.wb-header .wb-col[data-colid='${colId}'] [data-command='filter']`);
    if (!icon) {
      requestAnimationFrame(() => {
        const retryIcon = this.element?.querySelector(`.wb-header .wb-col[data-colid='${colId}'] [data-command='filter']`);
        if (!retryIcon) return;
        const retryActive = !!active;
        retryIcon.classList.toggle("filter-active", retryActive);
        retryIcon.classList.toggle("wb-helper-invalid", retryActive);
        retryIcon.dataset.filterActive = retryActive ? "true" : "false";
      });
      return;
    }
    const isActive = !!active;
    icon.classList.toggle("filter-active", isActive);
    icon.classList.toggle("wb-helper-invalid", isActive);
    icon.dataset.filterActive = isActive ? "true" : "false";
  }

  async _hydrateSingleParentByKey(parentKey, mySeq) {
    if (mySeq !== this._filterSeq) return;
    const pid = String(parentKey);
    if (!pid) return;
    if (this.loadedFolders.has(pid)) return;

    const parentNode = this._findNodeByKey(pid);
    if (!parentNode) return;

    let childFolders = this.folderCache.get(pid);
    if (!childFolders) {
      const ctrl = this._beginFetchGroup();
      try {
        childFolders = await this._fetchJson(
          `/volumes/${this.volumeIdValue}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(pid)}`,
          ctrl
        ).catch(() => []);
      } finally {
        this.inflightControllers.delete(ctrl);
      }
      if (!Array.isArray(childFolders)) childFolders = [];
      this.folderCache.set(pid, childFolders);
    }

    const existing = new Set((parentNode.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
    const toAdd = childFolders.filter((folder) => !existing.has(String(folder.key ?? folder.id)));
    if (toAdd.length) parentNode.addChildren?.(toAdd);

    this.loadedFolders.add(pid);
  }

  async _ensureAssetsForFolderCancellable(folderKey, mySeq) {
    const k = String(folderKey);
    if (this.assetsLoadedFor.has(k)) return;

    const node = this._findNodeByKey(k);
    if (!node || node.data?.folder !== true) { this.assetsLoadedFor.add(k); return; }
    let assets = this.assetCache.get(k);
    if (!assets) {
      const ctrl = this._beginFetchGroup();
      try {
        assets = await this._fetchJson(
          `/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(k)}`,
          ctrl
        ).catch(() => []);
      } finally {
        this.inflightControllers.delete(ctrl);
      }
      if (!Array.isArray(assets)) assets = [];
      this.assetCache.set(k, assets);
    }
    if (mySeq !== this._filterSeq) return;

    if (assets.length) {
      const existing = new Set((node.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
      const toAdd = assets.filter((asset) => !existing.has(String(asset.key ?? asset.id)));
      if (toAdd.length) node.addChildren?.(toAdd);
    }

    this.assetsLoadedFor.add(k);
  }

  async _materializeSearchResults(folders, assets, seq) {
    const paths = new Set();

    for (const folder of folders) {
      if (Array.isArray(folder.path)) {
        paths.add([...folder.path, folder.id].map(String).join(">"));
      }
    }

    for (const asset of assets) {
      if (Array.isArray(asset.path)) {
        const pid = asset.parent_folder_id ?? asset.folder_id;
        if (pid != null) {
          paths.add([...asset.path, pid].map(String).join(">"));
        }
      }
    }

    for (const path of paths) {
      if (seq !== this._filterSeq) return;
      await this._loadPath(path.split(">"), seq);
    }
  }

  async _loadPath(pathIds, seq) {
    for (const rawId of pathIds) {
      if (seq !== this._filterSeq) return;
      const id = String(rawId);
      if (!id) continue;
      await this._hydrateSingleParentByKey(id, seq);
      const node = this._findNodeByKey(id);
      if (!node) {
        return;
      }

      const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id);

      if (node && !node.expanded && !this.expandingNodes.has(nodeKey)) {
        this.expandingNodes.add(nodeKey);
        try {
          node.setExpanded(true);
        } finally {
          Promise.resolve().then(() => {
            this.expandingNodes.delete(nodeKey);
          });
        }
      }
    }
  }

  _optionsForColumn(colId) {
  switch (colId) {
    case "assigned_to":
      return this.userOptions ?? [];
    case "migration_status":
      return this.migrationStatusOptions ?? [];
    case "contentdm_collection_id":
      return this.contentdmCollectionOptions ?? [];
    case "aspace_collection_id":
      return this.aspaceCollectionOptions ?? [];
    default:
      return [];
  }
}
  
  _showDropdownFilter(anchorEl, colId, colIdx) {
    const existing = document.querySelector(`[data-popup-for='${colId}']`);
    if (existing) {
      existing.remove();
      return;
    }

    document.querySelectorAll(".wb-popup").forEach(p => p.remove());

    const popup = document.createElement("div");
    popup.classList.add("wb-popup");
    popup.setAttribute("data-popup-for", colId);

    const select = document.createElement("select");
    select.classList.add("popup-select");

    let opts = null;
    switch (colId) {
      case "migration_status":
        opts = this.migrationStatusOptions;
        break;
      case "aspace_collection_id":
        opts = this.aspaceCollectionOptions;
        break;
      case "contentdm_collection_id":
        opts = this.contentdmCollectionOptions;
        break;
      case "assigned_to":
        opts = this.userOptions;
        break;
    }

    if (opts) {
      const optionsMarkup = opts.map(o => `<option value="${String(o.value)}">${o.label}</option>`).join("");
      select.innerHTML = `${optionsMarkup}<option value="">⨉ Clear Filter</option>`;
    } else if (colId === "aspace_linking_status") {
      select.innerHTML = `
        <option value="true">True</option>
        <option value="false">False</option>
        <option value="">⨉ Clear Filter</option>
      `;
    } else {
      const values = this.columnValueCache.get(colId) ?? new Set();
      const sorted = [...values].sort();
      select.innerHTML =
        sorted.map((v) => `<option value="${v}">${v}</option>`).join("") +
        `<option value="">⨉ Clear Filter</option>`;
    }

    const currentFilter = this.columnFilters.has(colId)
      ? String(this.columnFilters.get(colId))
      : "";
    select.value = currentFilter;

    const expandSelect = () => {
      const visibleCount = Math.max(Math.min(select.options.length, 8), 4);
      select.size = visibleCount;
      select.classList.remove("popup-select--collapsed");
    };

    const collapseSelect = () => {
      select.removeAttribute("size");
      select.classList.add("popup-select--collapsed");
    };

    expandSelect();

    select.addEventListener("change", (e) => {
      const selectedValue = e.target.value;
      if (selectedValue === "") {
        this.columnFilters.delete(colId);
        const popupEl = document.querySelector(`[data-popup-for='${colId}']`);
        if (popupEl) popupEl.remove();
      } else {
        this.columnFilters.set(colId, selectedValue);
        collapseSelect();
      }

      const isActive = this.columnFilters.has(colId);
      const colDef = this.tree.columns.find(c => c.id === colId);
      if (colDef) colDef.filterActive = isActive;
      this._setFilterIconState(colId, isActive);

      this._runDeepFilter(this.currentQuery);
    });

    popup.appendChild(select);
    document.body.appendChild(popup);
    select.focus();

    const resolveColumnCell = () => {
      let cell = this.element?.querySelector(`.wb-header .wb-col[data-colid='${colId}']`);
      if (!cell && Number.isInteger(colIdx)) {
        const cols = this.element?.querySelectorAll(".wb-header .wb-col");
        cell = cols?.[colIdx];
      }
      return cell ?? anchorEl.closest(".wb-col") ?? anchorEl;
    };

    let rafId = null;
    const updatePos = () => {
      const columnCell = resolveColumnCell();
      if (!columnCell?.isConnected) {
        rafId = requestAnimationFrame(updatePos);
        return;
      }
      const r = columnCell.getBoundingClientRect();
      popup.style.position = "absolute";
      popup.style.left = `${window.scrollX + r.left}px`;
      popup.style.minWidth = `${r.width}px`;
      let top = window.scrollY + r.top - popup.offsetHeight - 4;
      if (top < window.scrollY) {
        top = window.scrollY + r.bottom + 4;
      }
      popup.style.top = `${top}px`;
      popup.style.zIndex = "1000";
      rafId = requestAnimationFrame(updatePos);
    };
    rafId = requestAnimationFrame(updatePos);

    const reposition = () => {
      if (rafId != null) cancelAnimationFrame(rafId);
      rafId = requestAnimationFrame(updatePos);
    };
    window.addEventListener("scroll", reposition, true);
    window.addEventListener("resize", reposition);

    const cleanup = () => {
      if (rafId != null) {
        cancelAnimationFrame(rafId);
        rafId = null;
      }
      window.removeEventListener("scroll", reposition, true);
      window.removeEventListener("resize", reposition);
      document.removeEventListener("mousedown", outsideClickHandler);
      popup.remove();
    };

    const outsideClickHandler = (e) => {
      if (!popup.contains(e.target) && !anchorEl.contains(e.target)) {
        cleanup();
      }
    };

    document.addEventListener("mousedown", outsideClickHandler);

    const obs = new MutationObserver(() => {
      if (!document.body.contains(popup)) {
        cleanup();
        obs.disconnect();
      }
    });
    obs.observe(document.body, { childList: true }); 
  }

  _beginFetchGroup() {
    const ctrl = new AbortController();
    this.inflightControllers.add(ctrl);
    return ctrl;
  }

  _cancelInflight() {
    for (const c of this.inflightControllers) { try { c.abort(); } catch {} }
    this.inflightControllers.clear();
  }

  async _fetchJson(url, ctrl) {
    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      signal: ctrl?.signal
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return res.json();
  }

  _setLoading(isLoading, text = "Loading…") {
    const input = document.getElementById("tree-filter");
    if (!input) return;

    let container = document.querySelector(".wb-loading-container");
    if (!container) {
      const toolbar = input.closest(".wb-toolbar") || input.parentElement;
      container = document.createElement("div");
      container.className = "wb-loading-container";
      toolbar.insertAdjacentElement("afterend", container);
    }

    let statusEl = container.querySelector(".wb-loading");
    if (!statusEl) {
      statusEl = document.createElement("div");
      statusEl.className = "wb-loading";
      container.appendChild(statusEl);
    }

    if (!isLoading) {
      statusEl.textContent = "";
      container.style.display = "none";
      return;
    }

    statusEl.textContent = text;
  }
  
  async _fetchOptions(url, targetProp) {
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" } });
      if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
      const data = await res.json();

      let opts = Object.entries(data).map(([id, name]) => ({
        value: String(id),
        label: name
      }));

      if (targetProp === "userOptions") {
        opts.unshift({ value: "unassigned", label: "Unassigned" });
      }

      this[targetProp] = opts;
    } catch (err) {
      console.error("Failed to fetch options for", url, err);
    }
  }

  async _saveCellChange(node, field, value) {
    const nodeId = node.key;
    const nodeType = node.data.folder ? "folder" : "asset";

    try {
      const resp = await fetch(`/volumes/${this.volumeIdValue}/file_tree_updates`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        },
        body: JSON.stringify({ node_id: nodeId, node_type: nodeType, field, value }),
        credentials: "same-origin",
      });

      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();
      
      node.data[field] = value;
    } catch (err) {
      console.error("Failed to save cell change", err);
    }
  }

  _emitSelectionChange() {
    const selectedAssetIds = this.tree.getSelectedNodes()
      .filter(node => !node.data.folder && node.key && node.key.startsWith('a-'))
      .map(node => parseInt(node.key.replace('a-', ''), 10))
      .filter(id => !isNaN(id));

    const selectedFolderIds = this.tree.getSelectedNodes()
      .filter(node => node.data.folder && node.key && !node.key.startsWith('a-'))
      .map(node => parseInt(node.key, 10))
      .filter(id => !isNaN(id));

    const event = new CustomEvent("wunderbaum:selectionChanged", {
      detail: { selectedAssetIds, selectedFolderIds }
    });
    document.dispatchEvent(event);
  }

  // Public method to clear selection (called by batch actions after successful update)
  clearSelection() {
    if (this.tree) {
      this.tree.setSelection(false);
    }
  }

  // Public method to refresh tree display after batch updates
  async refreshTreeDisplay(updatedAssetIds = [], updatedFolderIds = []) {
    
    if (this.tree && updatedFolderIds.length > 0) {
      
      for (const folderId of updatedFolderIds) {
        const nodeKey = folderId.toString(); // Folders use just the ID as key, not "f-" prefix
        const node = this.tree.findKey(nodeKey);
        
        if (node) {
          await this.refreshFolderNode(node, folderId);
        }
      }
    }
    
    if (this.tree && updatedAssetIds.length > 0) {
      const parentFolderIds = new Set();
      
      updatedAssetIds.forEach(assetId => {
        const nodeKey = `a-${assetId}`;
        const node = this.tree.findKey(nodeKey);
        if (node && node.data.parent_folder_id) {
          parentFolderIds.add(node.data.parent_folder_id);
        }
      });
      
      for (const folderId of parentFolderIds) {
        await this.refreshFolderAssets(folderId, updatedAssetIds);
      }
      
    } else if (updatedAssetIds.length === 0 && updatedFolderIds.length === 0) {
    }
  }

  async refreshFolderNode(node, folderId) {
    try {
      
      const response = await fetch(`/isilon_folders/${folderId}.json`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      
      if (response.ok) {
        const folderData = await response.json();
        
        Object.assign(node.data, folderData);
        
        node.setTitle(folderData.title);
        
        try {
          if (node.update) {
            node.update();
          } else if (node.renderColumns) {
            node.renderColumns();
          } else if (this.tree.update) {
            this.tree.update();
          } else {
            this.tree.redraw();
          }
        } catch (renderError) {
          console.error(`Failed to re-render folder node ${folderId}:`, renderError);
        }
        
      } else {
        console.error(`Failed to fetch folder data for ${folderId}:`, response.status);
      }
    } catch (error) {
      console.error(`Error refreshing folder node ${folderId}:`, error);
    }
  }

  async refreshFolderAssets(parentFolderId, updatedAssetIds) {
    try {
      
      const response = await fetch(`/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${parentFolderId}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      
      if (response.ok) {
        const assetsData = await response.json();
        
        assetsData.forEach(assetData => {
          const nodeKey = assetData.key; // Should be "a-{id}"
          const assetId = parseInt(nodeKey.replace('a-', ''), 10);
          
          if (updatedAssetIds.includes(assetId)) {
            const node = this.tree.findKey(nodeKey);
            if (node) {
              
              Object.assign(node.data, assetData);
              
              try {
                if (node.update) {
                  node.update();
                } else if (node.renderColumns) {
                  node.renderColumns();
                } else if (this.tree.update) {
                  this.tree.update();
                } else {
                  this.tree.redraw();
                }
              } catch (renderError) {
                console.error(`Failed to re-render node for asset ${assetId}:`, renderError);
              }
            }
          }
        });
      }
    } catch (error) {
      console.error(`Failed to refresh assets for folder ${parentFolderId}:`, error);
    }
  }
}
