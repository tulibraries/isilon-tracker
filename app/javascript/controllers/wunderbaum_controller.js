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

  selectLikeColumns = new Set([
    "migration_status",
    "assigned_to",
    "contentdm_collection_id",
    "aspace_collection_id"
  ]);

  folderSelectLikeColumns = new Set([
    "assigned_to"
  ]);

  // Initializes option vocabularies, builds the Wunderbaum instance, and wires all UI behavior.
  async connect() {
    const controller = this;
    await Promise.all([
      this._fetchOptions("/migration_statuses.json", "migrationStatusOptions"),
      this._fetchOptions("/aspace_collections.json", "aspaceCollectionOptions"),
      this._fetchOptions("/contentdm_collections.json", "contentdmCollectionOptions"),
      this._fetchOptions("/users.json", "userOptions")
    ]);

    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      const source = await res.json();

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
            width: "175px",
          },
          {
            id: "assigned_to",
            classes: "wb-helper-center",
            filterable: true,
            title: "Assigned To",
            width: "175px",
          },
          {
            id: "notes",
            classes: "wb-helper-center",
            title: "Notes",
            width: "500px",
            html: `<input type="text" name="notes" tabindex="-1">`
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
            width: "250px",
          },
          {
            id: "aspace_collection_id",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace Collection",
            width: "250px",
          },
          {
            id: "preservica_reference_id",
            classes: "wb-helper-center",
            title: "Preservica Reference",
            width: "200px",
            html: `<input type="text" name="preservica_reference_id" tabindex="-1">`
          },
          {
            id: "aspace_linking_status",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace linking status",
            width: "200px",
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

          this._reapplyFilterIfAny();
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
          const isFolder = node.data.folder === true;

          for (const colInfo of Object.values(e.renderColInfosById)) {
            const colId = colInfo.id;
            let rawValue = this._normalizeValue(colId, node.data[colId]);

            if (colId === "aspace_linking_status" && isFolder) {
              colInfo.elem.replaceChildren();
              colInfo.elem.classList.remove("wb-select-like");
              continue;
            }

            let displayValue = rawValue ?? "";

            if (this.selectLikeColumns.has(colId)) {
              displayValue = this._optionLabelFor(colId, rawValue);
            }

            colInfo.elem.dataset.colid = colId;

            if (this.selectLikeColumns.has(colId) && displayValue !== "") {
              colInfo.elem.classList.add("wb-select-like");
            } else {
              colInfo.elem.classList.remove("wb-select-like");
            }

            util.setValueToElem(colInfo.elem, displayValue);
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
    
      this._setupInlineFilter();
      this._setupClearFiltersButton();
      this._setupFilterModeToggle();

      this.element.addEventListener("pointerdown", (e) => {
        const cell = e.target.closest(".wb-select-like");
        if (!cell) return;

        const colId = cell.dataset.colid;
        if (!this.selectLikeColumns.has(colId)) return;

        const node = Wunderbaum.getNode(cell);
        if (!node) return;

        e.preventDefault();
        e.stopPropagation();

        this._showInlineEditor(cell, node, colId);
      });

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);    }
  }

  // Cancels pending async work and timers when the controller is removed.
  disconnect() {
    clearTimeout(this._filterTimer);
    this._cancelInflight();
  }

  // Wires the text filter input and Escape key behavior.
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

  // Wires the “Clear Filters” button to fully reset tree state.
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

  // Executes backend-backed filtering and materializes matching paths.
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

  // Applies the current filter predicate to the tree.
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

  // Reapplies the active filter after node expansion.
  _reapplyFilterIfAny() {
    if (this.currentFilterPredicate) {
      const opts = { ...(this.currentFilterOpts || {}), mode: this.filterMode };
      this.currentFilterOpts = opts;
      this.tree.filterNodes(this.currentFilterPredicate, opts);
    }
    this._updateFilterModeButton();
  }

  // Finds a tree node by its key.
  _findNodeByKey(key) {
    const skey = String(key);
    return this.tree?.findKey?.(skey) ?? null;
  }

  // Toggles between hide and dim filter modes.
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

  // Updates the filter mode toggle UI state.
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

  // Updates column filter icon state in the header.
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

  // Ensures a folder’s immediate child folders are loaded.
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

  // Loads assets for a folder with cancellation support.
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

  // Ensures all folder paths needed for search results exist.
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

  // Expands and loads each folder along a given path.
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

  // Normalizes stored values for display and editing.
  _normalizeValue(colId, value) {
    if (colId === "assigned_to" && (value == null || value === "")) {
      return "unassigned";
    }
    return value;
  }

  // Returns the option list for a select-like column.
  _optionsForColumn(colId) {
    return this[{
      assigned_to: "userOptions",
      migration_status: "migrationStatusOptions",
      contentdm_collection_id: "contentdmCollectionOptions",
      aspace_collection_id: "aspaceCollectionOptions"
    }[colId]] ?? [];
  }

  // Resolves a stored value to its human-readable label.
  _optionLabelFor(colId, value) {
    if (value == null || value === "") return "";

    const opts = this._optionsForColumn(colId);
    if (!opts || !opts.length) return String(value);

    const found = opts.find(o => String(o.value) === String(value));
    return found ? found.label : String(value);
  }
  
  // Displays and manages the column filter dropdown popup.
  _showDropdownFilter(anchorEl, colId, colIdx, opts = {}) {
    const isInline = typeof opts.onSelect === "function";

    const existing = document.querySelector(`[data-popup-for='${colId}']`);
    if (existing) {
      existing.remove();
      return;
    }

    document.querySelectorAll(".wb-popup").forEach(p => p.remove());

    const popup = document.createElement("div");
    popup.className = "wb-popup";
    popup.dataset.popupFor = colId;

    const select = document.createElement("select");
    select.className = "popup-select";

    let options = [];

    if (colId === "assigned_to") {
      options = this.userOptions || [];
    } else if (colId === "migration_status") {
      options = this.migrationStatusOptions || [];
    } else if (colId === "contentdm_collection_id") {
      options = this.contentdmCollectionOptions || [];
    } else if (colId === "aspace_collection_id") {
      options = this.aspaceCollectionOptions || [];
    } else if (colId === "aspace_linking_status") {
      options = [
        { value: "true", label: "True" },
        { value: "false", label: "False" }
      ];
    } else {
      const values = this.columnValueCache.get(colId) || new Set();
      options = [...values].sort().map(v => ({ value: v, label: v }));
    }

    for (const o of options) {
      const opt = document.createElement("option");
      opt.value = String(o.value);
      opt.textContent = o.label;
      select.appendChild(opt);
    }

    if (!isInline) {
      const clearOpt = document.createElement("option");
      clearOpt.value = "";
      clearOpt.textContent = "⨉ Clear Filter";
      select.appendChild(clearOpt);
    }

    if (isInline) {
      select.size = Math.min(select.options.length, 8);
    } else {
      select.size = Math.max(Math.min(select.options.length, 8), 4);
    }
    
    if (isInline) {
      select.value = "";
    } else {
      select.value = this.columnFilters.has(colId)
        ? String(this.columnFilters.get(colId))
        : "";
    }

    select.addEventListener("change", (e) => {
      const value = e.target.value;

      if (isInline) {
        opts.onSelect(value);
        popup.remove();
        return;
      }

      if (value === "") {
        this.columnFilters.delete(colId);
        popup.remove();
      } else {
        this.columnFilters.set(colId, value);
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
      if (anchorEl.closest(".wb-col")) return anchorEl.closest(".wb-col");
      if (Number.isInteger(colIdx)) {
        const cols = this.element.querySelectorAll(".wb-header .wb-col");
        return cols[colIdx] || anchorEl;
      }
      return anchorEl;
    };

    let rafId = null;

    const updatePosition = () => {
      const cell = resolveColumnCell();
      if (!cell || !cell.isConnected) {
        rafId = requestAnimationFrame(updatePosition);
        return;
      }

      const r = cell.getBoundingClientRect();
      popup.style.position = "absolute";
      popup.style.left = `${window.scrollX + r.left}px`;
      popup.style.minWidth = `${r.width}px`;

      let top = window.scrollY + r.top - popup.offsetHeight - 4;
      if (top < window.scrollY) {
        top = window.scrollY + r.bottom + 4;
      }

      popup.style.top = `${top}px`;
      popup.style.zIndex = "1000";

      rafId = requestAnimationFrame(updatePosition);
    };

    rafId = requestAnimationFrame(updatePosition);

    const cleanup = () => {
      if (rafId) cancelAnimationFrame(rafId);
      document.removeEventListener("mousedown", outsideClick);
      window.removeEventListener("scroll", updatePosition, true);
      window.removeEventListener("resize", updatePosition);
      popup.remove();
    };

    const outsideClick = (e) => {
      if (!popup.contains(e.target) && !anchorEl.contains(e.target)) {
        cleanup();
      }
    };

    document.addEventListener("mousedown", outsideClick);
    window.addEventListener("scroll", updatePosition, true);
    window.addEventListener("resize", updatePosition);
  }

  _showInlineEditor(cell, node, colId) {
    this._showDropdownFilter(cell, colId, null, {
      onSelect: (value) => {
        const normalized = this._normalizeValue(colId, value);
        node.data[colId] = normalized;
        this._saveCellChange(node, colId, normalized);

        const label = this._optionLabelFor(colId, normalized);
        cell.textContent = label || "Unassigned";
        cell.classList.add("wb-select-like");
      }
    });
  }

  _showInlineDropdown(cell, node, colId) {
    document.querySelectorAll(".wb-popup").forEach(p => p.remove());

    const popup = document.createElement("div");
    popup.className = "wb-popup";

    const list = document.createElement("div");
    list.className = "popup-select popup-select--expanded";

    const opts = this._optionsForColumn(colId);
    const current = String(this._normalizeValue(colId, node.data[colId]));

    for (const o of opts) {
      const item = document.createElement("div");
      item.className = "wb-popup-item";
      item.textContent = o.label;
      item.dataset.value = o.value;

      if (String(o.value) === current) {
        item.classList.add("active");
      }

      item.addEventListener("mousedown", (e) => {
        e.preventDefault();
        popup.remove();
      });

      list.appendChild(item);
    }

    popup.appendChild(list);
    document.body.appendChild(popup);

    this._positionPopup(popup, cell);

    document.addEventListener("mousedown", (e) => {
      if (!popup.contains(e.target)) popup.remove();
    }, { once: true });
  }

  // Creates and tracks an AbortController for grouped requests.
  _beginFetchGroup() {
    const ctrl = new AbortController();
    this.inflightControllers.add(ctrl);
    return ctrl;
  }

  // Cancels all in-flight network requests.
  _cancelInflight() {
    for (const c of this.inflightControllers) { try { c.abort(); } catch {} }
    this.inflightControllers.clear();
  }

  // Fetches JSON with abort support.
  async _fetchJson(url, ctrl) {
    const res = await fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin",
      signal: ctrl?.signal
    });
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`);
    return res.json();
  }

  // Shows or hides the loading indicator during async work.
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
  
  // Loads vocabulary options for select-like columns.
  async _fetchOptions(url, targetProp) {
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
  }

  // Persists inline edits to the backend.
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

  // Dispatches selected folder and asset IDs to the app.
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

  // Clears all selected nodes in the tree. (called by batch actions after successful update)
  clearSelection() {
    if (this.tree) {
      this.tree.setSelection(false);
    }
  }

  // Refreshes tree nodes after batch updates.
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

  // Reloads and re-renders a single folder node.
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

  // Reloads and updates asset nodes under a folder.
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
