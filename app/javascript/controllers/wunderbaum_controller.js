import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, volumeId: Number };

  columnFilters = new Map();
  assetsLoadedFor = new Set();
  expandedByFilter = new Set();
  currentFilterPredicate = null;
  currentFilterOpts = null;
  currentQuery = "";
  filterMode = "hide";
  folderCache = new Map();
  assetCache = new Map();
  loadedFolders = new Set();
  loadedAssets = new Set();
  _pendingChains = [];
  _pendingChainKeys = new Set();
  _pendingChainHandle = null;
  _expandingChains = false;

  inflightControllers = new Set();
  _filterTimer = null;
  _filterSeq = 0;

  initialize() {
    this.isVirtualTree = true;
  }

  async connect() {
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
        grid: { debounce: 0 }, 
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
            html: `<select tabindex="-1"><option value="1" selected>Needs Review</option></select>`
          },
          {
            id: "assigned_to",
            classes: "wb-helper-center",
            filterable: true,
            title: "Assigned To",
            width: "150px",
            html: `<select tabindex="-1"><option value="assigned_to" selected>unassigned</option></select>`
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
            html: `<select tabindex="-1"><option value="" selected></option></select>`
          },
          {
            id: "aspace_collection_id",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace Collection",
            width: "150px",
            html: `<select tabindex="-1"><option value="" selected></option></select>`
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

        lazyLoad: (e) => this._lazyLoadFolderChildren(e),

        expand: (e) => {
          const node = e.node
          if (!node?.data?.folder) return
          requestAnimationFrame(() => {
            this._ensureAssetsForFolderCancellable(
              String(node.key ?? node.data?.key ?? node.data?.id),
              this._filterSeq
            ).then(() => this._reapplyFilterIfAny())
          })
        },

        postProcess: (e) => { e.result = e.response; },

        renderHeaderCell: (e) => {
          const { colDef, cellElem } = e.info;
          cellElem.dataset.colid = colDef.id;
          this._setFilterIconState(colDef.id, colDef.filterActive);
        },

        render: (e) => {
          const util = e.util;
          const isFolder = e.node.data.folder === true;

          for (const colInfo of Object.values(e.renderColInfosById)) {
            const colId = colInfo.id;
            let value = e.node.data[colId];
            let elem = colInfo.elem;

            switch (colId) {
              case "migration_status":
              case "aspace_collection_id":
              case "contentdm_collection_id":
              case "assigned_to": {
                const options =
                  colId === "migration_status"
                    ? this.migrationStatusOptions
                    : colId === "aspace_collection_id"
                    ? this.aspaceCollectionOptions
                    : colId === "contentdm_collection_id"
                    ? this.contentdmCollectionOptions
                    : this.userOptions;

                if (!options) {
                  util.setValueToElem(elem, value ?? "");
                  break;
                }

                if (!elem.dataset.rendered) {
                  const select = document.createElement("select");
                  select.name = colId;
                  options.forEach((opt) => {
                    const option = document.createElement("option");
                    option.value = String(opt.value);
                    option.textContent = opt.label;
                    select.appendChild(option);
                  });
                  elem.replaceChildren(select);
                  elem.dataset.rendered = "true";
                }

                const select = elem.querySelector("select");
                if (select) select.value = value ?? "";
                break;
              }

              case "notes":
              case "preservica_reference_id": {
                if (isFolder) {
                  util.setValueToElem(elem, "");
                  break;
                }
                if (!elem.dataset.rendered) {
                  const input = document.createElement("input");
                  input.type = "text";
                  input.name = colId;
                  elem.replaceChildren(input);
                  elem.dataset.rendered = "true";
                }
                const input = elem.querySelector("input");
                if (input) input.value = value ?? "";
                break;
              }

              case "aspace_linking_status": {
                if (isFolder) {
                  util.setValueToElem(elem, "");
                  break;
                }
                if (!elem.dataset.rendered) {
                  const checkbox = document.createElement("input");
                  checkbox.type = "checkbox";
                  checkbox.name = colId;
                  elem.replaceChildren(checkbox);
                  elem.dataset.rendered = "true";
                }
                const checkbox = elem.querySelector("input");
                if (checkbox) checkbox.checked = Boolean(value);
                break;
              }

              default:
                util.setValueToElem(elem, value ?? "");
            }
          }

          const titleElem = e.nodeElem.querySelector("span.wb-title");
          if (titleElem) {
            if (isFolder) {
              titleElem.textContent = e.node.title || "";
            } else {
              titleElem.innerHTML = `<a href="${e.node.data.url}" class="asset-link" data-turbo="false">${e.node.title}</a>`;
            }
          }
        },

        buttonClick: (e) => {
          console.log("ButtonClick triggered for:", e.command, e.info?.colDef?.id);
          if (e.command === "filter") {
            const colId = e.info.colDef.id;
            const colIdx = e.info.colIdx;
            const allCols = this.element.querySelectorAll(".wb-header .wb-col");
            const colCell = allCols[colIdx];
            if (!colCell) return;
            const icon = colCell.querySelector("[data-command='filter']");
            if (!icon) return;
            this.showDropdownFilter(icon, colId, colIdx);
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

      requestAnimationFrame(() => {
        const t = this.tree
        const listEl = t.listContainerElement
        t.scrollParent = listEl

        if (listEl) {
          const root = t.root
          const parentId = root?.key || "root"
          let nextPage = 2

          listEl.addEventListener("scroll", async () => {
            if (listEl.scrollTop + listEl.clientHeight >= listEl.scrollHeight - 100) {
              if (nextPage) nextPage = await this._loadNextAssetPage(parentId, nextPage)
            }
            if (t.updateViewport) t.updateViewport()
            else if (t._updateViewportThrottled) t._updateViewportThrottled()
          })
        }
      })

      const listEl = this.tree.listContainerElement
        if (listEl) {
          listEl.addEventListener("scroll", () => this.tree.updateViewport?.(), { passive: true })
        }

      this._fetchOptions("/migration_statuses.json", "migrationStatusOptions", "migration_status");
      this._fetchOptions("/aspace_collections.json", "aspaceCollectionOptions", "aspace_collection_id");
      this._fetchOptions("/contentdm_collections.json", "contentdmCollectionOptions", "contentdm_collection_id");
      this._fetchOptions("/users.json", "userOptions", "assigned_to");

      this._setupInlineFilter();
      this._setupClearFiltersButton();
      this._setupFilterModeToggle();
      requestAnimationFrame(() => {
        this._tagHeaderCells()
        this._deferSelectHydration()
      })

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }

    this._onTreeScroll = this._onTreeScroll.bind(this);
    this.element.addEventListener("scroll", this._onTreeScroll, { passive: true });
  }

  disconnect() {
    clearTimeout(this._filterTimer);
    this._cancelInflight();
    if (this._onTreeScroll) {
      this.element.removeEventListener("scroll", this._onTreeScroll);
    }
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
      this.loadedAssets.clear();
      this._pendingChains = [];
      this._pendingChainKeys.clear();
      if (this._pendingChainHandle != null) {
        if (typeof cancelIdleCallback === "function") {
          cancelIdleCallback(this._pendingChainHandle);
        } else {
          clearTimeout(this._pendingChainHandle);
        }
        this._pendingChainHandle = null;
      }
      this._expandingChains = false;
      if (this.tree?.options?.filter) {
        this.tree.options.filter.mode = this.filterMode;
      }

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

      this.tree.clearFilter();
      if (this.tree?.visit) {
        this.tree.visit((node) => {
          if (node.expanded) node.setExpanded(false);
        });
      }
      this._collapseFilterExpansions();
      this._setLoading(false);
      this._updateFilterModeButton();
    });
  }

  async _runDeepFilter(raw) {
    this._cancelInflight();
    const mySeq = ++this._filterSeq;
    this.loadedFolders.clear();
    this.loadedAssets.clear();
    this._pendingChains = [];
    this._pendingChainKeys = new Set();
    if (this._pendingChainHandle != null) {
      if (typeof cancelIdleCallback === "function") {
        cancelIdleCallback(this._pendingChainHandle);
      } else {
        clearTimeout(this._pendingChainHandle);
      }
      this._pendingChainHandle = null;
    }
    this._expandingChains = false;

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
      const fetchAllPages = async (urlBase) => {
        let results = []
        let next = urlBase
        while (next) {
          const resp = await fetch(next, {
            headers: { Accept: "application/json" },
            credentials: "same-origin",
            signal: searchCtrl?.signal
          })
          if (!resp.ok) break
          const data = await resp.json()
          results = results.concat(data.results || data)
          next = data.next_page ? `${urlBase}&page=${data.next_page}` : null
          await new Promise(r => requestAnimationFrame(r))
        }
        return results
      }

      [folders, assets] = await Promise.all([
        fetchAllPages(`/volumes/${this.volumeIdValue}/file_tree_folders_search.json?${params.toString()}`),
        fetchAllPages(`/volumes/${this.volumeIdValue}/file_tree_assets_search.json?${params.toString()}`)
      ])
    } finally {
      this.inflightControllers.delete(searchCtrl);
    }
    if (mySeq !== this._filterSeq) return;

    const chains = this._buildMatchChains(folders, assets);
    await this._expandChainsImmediate(chains, mySeq);
    if (mySeq !== this._filterSeq) return;

    this._applyPredicate(q);

    requestAnimationFrame(() => {
      const tree = this.tree;
      if (tree && typeof tree.updateViewport === "function") {
        tree.updateViewport();
      } else if (tree && tree._updateViewportThrottled) {
        tree._updateViewportThrottled();
      }
    });

    this._setLoading(false);
 }

  _applyPredicate(q) {
    const predicate = (node) => {
      if (q) {
        const t = (node.title || "").toLowerCase();
        if (!t.includes(q)) return false;
      }
      for (const [colId, val] of this.columnFilters.entries()) {
        const nv = node.data[colId];
        if (nv == null || String(nv).toLowerCase() !== String(val).toLowerCase()) return false;
      }
      return true;
    };

    this.currentFilterPredicate = predicate;
    this.currentFilterOpts = { mode: this.filterMode };

    this.tree.filterNodes(predicate, this.currentFilterOpts);
    this._updateFilterModeButton();
  }

  _reapplyFilterIfAny() {
    if (this.currentFilterPredicate) {
      this.tree.filterNodes(this.currentFilterPredicate, { mode: this.filterMode });
    }
    this._updateFilterModeButton();
  }

  _findNodeByKey(key) {
    const skey = String(key);
    let n = this.tree.getNodeByKey?.(skey);
    if (n) return n;
    this.tree.visit((node) => {
      const k = String(node.key ?? node.data?.key ?? node.data?.id);
      if (k === skey) { n = node; return false; }
    });
    return n;
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
      if (this.currentFilterPredicate) {
        this.tree.filterNodes(this.currentFilterPredicate, { mode: this.filterMode });
      }
      this._updateFilterModeButton();
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
      icon.classList.add(isHideMode ? "bi-filter-square-fill" : "bi-filter-square");
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

  _tagHeaderCells() {
    const cells = this.element?.querySelectorAll(".wb-header .wb-col");
    if (!cells || !this.tree?.columns) return;
    cells.forEach((cell, idx) => {
      const colDef = this.tree.columns[idx];
      if (!colDef) return;
      if (!cell.dataset.colid) cell.dataset.colid = colDef.id;
      this._setFilterIconState(colDef.id, colDef.filterActive);
    });
  }

_handleInputChange(e) {
  const target = e.target;
  if (!(target instanceof HTMLSelectElement || target instanceof HTMLInputElement)) return;

  const nodeKey = target.dataset.nodeKey || target.closest(".wb-node")?.dataset.key;
  if (!nodeKey) {
    console.warn("No nodeKey found for target:", target);
    return;
  }

  const node = this._findNodeByKey(nodeKey);
  if (!node) {
    console.warn("No node found for nodeKey:", nodeKey);
    return;
  }

  const colCell = target.closest(".wb-col");
  const field = colCell?.dataset.colid || target.name;
  if (!field) {
    console.warn("No field resolved for target:", target);
    return;
  }

  let value;
  if (target.type === "checkbox") {
    value = target.checked;
  } else {
    value = target.value;
  }

  node.data[field] = value;
  this._saveCellChange(node, field, value);
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

  async _fetchFolderChildren(parentId) {
    const url = `/volumes/${this.volumeIdValue}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(String(parentId))}`;
    const resp = await fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    });
    if (!resp.ok) throw new Error(`Folder fetch failed with ${resp.status}`);
    const data = await resp.json();

    const cacheKey = parentId == null ? "root" : String(parentId);
    this.folderCache.set(cacheKey, data);
    this.loadedFolders.add(cacheKey);
    return data;
  }

  async _ensureAssetsForFolderCancellable(folderKey, mySeq) {
    const k = String(folderKey)
    if (this.assetsLoadedFor.has(k)) return

    const node = this._findNodeByKey(k)
    if (!node || node.data?.folder !== true) {
      this.assetsLoadedFor.add(k)
      return
    }

    let assets = this.assetCache.get(k)
    if (!assets) {
      const ctrl = this._beginFetchGroup()
      try {
        assets = await this._fetchJson(
          `/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(k)}`,
          ctrl
        ).catch(() => [])
      } finally {
        this.inflightControllers.delete(ctrl)
      }
      if (!Array.isArray(assets)) assets = []
      this.assetCache.set(k, assets)
    }

    if (mySeq !== this._filterSeq) return
    if (!assets.length) {
      this.assetsLoadedFor.add(k)
      this.loadedAssets.add(k)
      return
    }

    const children = assets.map(a => ({
      key: a.key ?? `a-${a.id}`,
      title: a.title ?? a.name ?? a.filename ?? `Asset ${a.id}`,
      folder: false,
      ...a
    }))

    const INITIAL_RENDER_LIMIT = 20
    const CHUNK_SIZE = 10

    const initial = children.slice(0, INITIAL_RENDER_LIMIT)
    const remaining = children.slice(INITIAL_RENDER_LIMIT)

    if (initial.length) node.addChildren(initial)

    if (remaining.length) {
      let i = 0
      const schedule = () => {
        if (i >= remaining.length) {
          this.assetsLoadedFor.add(k)
          this.loadedAssets.add(k)
          this.tree?.updateViewport?.()
          return
        }
        const slice = remaining.slice(i, i + CHUNK_SIZE)
        i += CHUNK_SIZE
        node.addChildren(slice)
        this.tree?.updateViewport?.()
        requestIdleCallback(schedule, { timeout: 200 })
      }
      requestIdleCallback(schedule, { timeout: 200 })
    } else {
      this.assetsLoadedFor.add(k)
      this.loadedAssets.add(k)
    }
  }

  async _expandPathCancellable(pathIds, mySeq) {
    const hops = pathIds.map(id => String(id));

    for (let i = 0; i < hops.length; i++) {
      if (mySeq !== this._filterSeq) return;

      const hopKey = hops[i];
      let node = this._findNodeByKey(hopKey);

      if (!node) {
        const parentKey = i > 0 ? hops[i - 1] : null;
        if (parentKey != null) {
          await this._hydrateSingleParentByKey(parentKey, mySeq);
          node = this._findNodeByKey(hopKey);
        }
        if (!node) return;
      }

      if (!node.children || node.children.length === 0) {
        await this._hydrateSingleParentByKey(hopKey, mySeq);
      }

      if ((!node.children || node.children.length === 0) && node.lazy) {
        try { await node.loadLazy(); } catch {}
      }

      if (!node.expanded) {
        node.setExpanded?.(true);
        this.expandedByFilter.add(String(node.key ?? node.data?.key ?? node.data?.id));
      }

      await this._ensureAssetsForFolderCancellable(String(node.key ?? node.data?.key ?? node.data?.id), mySeq);

      await new Promise(r => requestAnimationFrame(r));
    }
  }

  _buildMatchChains(folders = [], assets = []) {
    const chains = [];

    for (const folder of folders || []) {
      const path = Array.isArray(folder.path) ? folder.path : [];
      const ids = [...path, folder.id].filter((id) => id != null);
      if (!ids.length) continue;
      chains.push({ chain: ids.map(String), assetParentId: null });
    }

    for (const asset of assets || []) {
      const path = Array.isArray(asset.path) ? asset.path : [];
      const pid = asset.parent_folder_id ?? asset.folder_id ?? asset.parent_id;
      const ids = pid != null ? [...path, pid] : path;
      if (!ids.length) continue;
      chains.push({ chain: ids.map(String), assetParentId: pid != null ? String(pid) : null });
    }

    return chains;
  }

  async _expandChainsImmediate(chains = [], seq) {
    for (const item of chains) {
      if (seq !== this._filterSeq) return;
      await this._loadPath(item.chain, seq);
      if (item.assetParentId) {
        await this._ensureAssetsForFolderCancellable(item.assetParentId, seq);
      }
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }
  }

  _enqueueChains(chains = [], seq) {
    for (const item of chains) {
      const key = `${item.chain.join(">")}|${item.assetParentId ?? ""}`;
      if (this._pendingChainKeys.has(key)) continue;
      this._pendingChainKeys.add(key);
      this._pendingChains.push({ ...item, seq });
    }
  }

  _schedulePendingChainExpansion() {
    if (this._expandingChains || !this._pendingChains.length) return;
    if (this._pendingChainHandle != null) return;

    const callback = () => {
      this._pendingChainHandle = null;
      this._expandPendingChains(this._filterSeq, 5);
    };

    if (typeof requestIdleCallback === "function") {
      this._pendingChainHandle = requestIdleCallback(callback, { timeout: 200 });
    } else {
      this._pendingChainHandle = setTimeout(callback, 0);
    }
  }

  _deferSelectHydration() {
    if (typeof requestIdleCallback !== "function") return
    requestIdleCallback(() => {
      this.tree?.visit(node => {
        if (!node.data.folder) node.renderColumns?.()
      })
    }, { timeout: 300 })
  }

  async _expandPendingChains(seq, limit) {
    if (this._expandingChains) return;
    this._expandingChains = true;
    let processed = 0;

    while (processed < limit && this._pendingChains.length) {
      if (seq !== this._filterSeq) break;
      const item = this._pendingChains.shift();
      const key = `${item.chain.join(">")}|${item.assetParentId ?? ""}`;
      this._pendingChainKeys.delete(key);
      if (item.seq !== this._filterSeq) continue;
      await this._loadPath(item.chain, item.seq);
      if (item.assetParentId) {
        await this._ensureAssetsForFolderCancellable(item.assetParentId, item.seq);
      }
      processed += 1;
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }

    this._expandingChains = false;
    if (this._pendingChains.length) this._schedulePendingChainExpansion();
  }

  async _loadPath(pathIds, seq) {
    for (const rawId of pathIds) {
      if (seq !== this._filterSeq) return;
      const id = String(rawId);
      if (!id) continue;
      await this._hydrateSingleParentByKey(id, seq);
      const node = this._findNodeByKey(id);
      if (node && !node.expanded) {
        node.setExpanded(true);
        this.expandedByFilter.add(String(node.key ?? node.data?.key ?? node.data?.id));
      }
    }
  }

  _onTreeScroll() {
    if (!this._pendingChains.length) return;
    const el = this.element;
    if (!el) return;

    const nearTop = el.scrollTop <= 200;
    const nearBottom = el.scrollTop + el.clientHeight >= el.scrollHeight - 400;
    if (nearTop || nearBottom) this._schedulePendingChainExpansion();
  }

  async _expandAllMatchChainsCancellable(folderHits, assetHits, mySeq, chunkSize = 10) {
    const chains = [];

    for (const f of folderHits) {
      const path = Array.isArray(f.path) ? f.path : [];
      chains.push([...path, f.id]);
    }
    for (const a of assetHits) {
      const path = Array.isArray(a.path) ? a.path : [];
      const pid = a.parent_folder_id ?? a.folder_id ?? a.parent_id;
      if (pid != null) chains.push([...path, pid]);
    }

    const seen = new Set(), uniq = [];
    for (const c of chains) {
      const k = c.map(x => String(x)).join(">");
      if (!seen.has(k)) { seen.add(k); uniq.push(c); }
    }

    for (let i = 0; i < uniq.length; i += chunkSize) {
      if (mySeq !== this._filterSeq) return;

      const batch = uniq.slice(i, i + chunkSize);
      await Promise.all(batch.map(chain => this._expandPathCancellable(chain, mySeq)));

      this._reapplyFilterIfAny();

      const done = Math.min(i + chunkSize, uniq.length);
      this._setLoading(true, `Loading results… (${done}/${uniq.length})`);

      await new Promise(r => requestAnimationFrame(r));
    }
  }

  _enqueueLazyAssetBatches(node, assets) {
    const queue = [...assets]
    const BATCH_SIZE = 50

    const processNext = () => {
      const batch = queue.splice(0, BATCH_SIZE)
      if (batch.length) node.addChildren(batch)
      if (queue.length) {
        requestIdleCallback(processNext, { timeout: 200 })
      } else {
        requestAnimationFrame(() => {
          const t = node.tree
          if (t.updateViewport) t.updateViewport()
        })
      }
    }

    requestIdleCallback(processNext, { timeout: 200 })
  }

  _autoExpandSomeMatchingFolders(cap = 20) {
    if (!this.currentFilterPredicate || !this.tree) return;
    let expanded = 0;
    this.tree.visit((node) => {
      if (expanded >= cap) return false;
      const isFolder = node.data?.folder === true;
      if (!isFolder) return;
      let matched = false;
      try { matched = this.currentFilterPredicate(node); } catch {}
      if (!matched) return;
      if (!node.expanded) {
        node.setExpanded(true);
        this.expandedByFilter.add(String(node.key ?? node.data?.key ?? node.data?.id));
        expanded += 1;
      }
    });
  }

  _collapseFilterExpansions() {
    for (const key of this.expandedByFilter) {
      const node = this._findNodeByKey(key);
      if (node && node.expanded) node.setExpanded(false);
    }
    this.expandedByFilter.clear();
  }
  
  showDropdownFilter(anchorEl, colId, colIdx) {
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
      const values = new Set();
      this.tree.visit((node) => {
        const val = node.data[colId];
        if (val != null) values.add(val);
      });
      const sorted = [...values].map(String).sort();
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
      requestAnimationFrame(() => updatePos());
    };

    const collapseSelect = () => {
      select.removeAttribute("size");
      select.classList.add("popup-select--collapsed");
      requestAnimationFrame(() => updatePos());
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
    })
    if (!res.ok) throw new Error(`HTTP ${res.status} for ${url}`)
    return res.json()
  }

async _batchAddChildren(node, items, chunkSize = 10, delayMs = 10) {
  if (!items?.length) return
  let i = 0
  while (i < items.length) {
    const slice = items.slice(i, i + chunkSize)
    try {
      node.addChildren?.(slice)
    } catch {
      for (const it of slice) {
        try { node.addChildren?.([it]) } catch {}
      }
    }
    i += chunkSize
    await new Promise(r => requestAnimationFrame(r))
  }
}

_enqueueBackgroundAdd(k, node, items, chunkSize = 10) {
  this._bgAddQueue = this._bgAddQueue || []
  this._bgAddQueue.push({ k, node, items, chunkSize })
  this._processBgAdds()
}

async _processBgAdds() {
  if (this._bgAddRunning) return
  this._bgAddRunning = true
  this._bgAddQueue = this._bgAddQueue || []
  while (this._bgAddQueue.length) {
    const { k, node, items, chunkSize } = this._bgAddQueue.shift()
    try {
      await this._batchAddChildren(node, items, chunkSize)
    } finally {
      this.assetsLoadedFor.add(k)
      this.loadedAssets.add(k)
    }
    await new Promise(r => setTimeout(r, 30))
  }
  this._bgAddRunning = false
  requestAnimationFrame(() => {
    this.tree?.updateViewport?.()
  })
}

async _loadNextAssetPage(parentId, nextPage) {
  const base = `/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${parentId}`
  const url = `${base}&page=${nextPage}`
  const data = await this._fetchJson(url)
  const assets = data.results || []
  const node = this._findNodeByKey(String(parentId))

  if (node && assets.length) {
    for (let i = 0; i < assets.length; i++) {
      node.addChildren([assets[i]])
      if (i % 10 === 0) await new Promise(r => requestAnimationFrame(r))
    }
  }

  return data.next_page
}

  _setLoading(isLoading, text = "Loading…") {
    const input = document.getElementById("tree-filter");
    if (!input) return;

    // Try to find or create a stable container just below the toolbar row
    let container = document.querySelector(".wb-loading-container");
    if (!container) {
      // Create a new container right *after* the toolbar row (not inside it)
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
    // Get selected asset IDs (excluding folders)
    const selectedAssetIds = this.tree.getSelectedNodes()
      .filter(node => !node.data.folder && node.key && node.key.startsWith('a-'))
      .map(node => parseInt(node.key.replace('a-', ''), 10))
      .filter(id => !isNaN(id));

    // Get selected folder IDs
    const selectedFolderIds = this.tree.getSelectedNodes()
      .filter(node => node.data.folder && node.key && !node.key.startsWith('a-'))
      .map(node => parseInt(node.key, 10))
      .filter(id => !isNaN(id));

    // Emit custom event for batch actions controller
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
    
    // Handle updated folders first
    if (this.tree && updatedFolderIds.length > 0) {
      
      for (const folderId of updatedFolderIds) {
        const nodeKey = folderId.toString(); // Folders use just the ID as key, not "f-" prefix
        const node = this.tree.findKey(nodeKey);
        
        if (node) {
          // Refresh the folder node by re-fetching its data
          await this.refreshFolderNode(node, folderId);
        }
      }
    }
    
    // Handle updated assets
    if (this.tree && updatedAssetIds.length > 0) {
      
      // Get unique parent folder IDs for the updated assets
      const parentFolderIds = new Set();
      
      updatedAssetIds.forEach(assetId => {
        const nodeKey = `a-${assetId}`;
        const node = this.tree.findKey(nodeKey);
        if (node && node.data.parent_folder_id) {
          parentFolderIds.add(node.data.parent_folder_id);
        }
      });
      
      // Refresh assets for each affected parent folder
      for (const folderId of parentFolderIds) {
        await this.refreshFolderAssets(folderId, updatedAssetIds);
      }
      
    } else if (updatedAssetIds.length === 0 && updatedFolderIds.length === 0) {
    }
  }

  async refreshFolderNode(node, folderId) {
    try {
      
      // Fetch fresh folder data using the show endpoint
      const response = await fetch(`/isilon_folders/${folderId}.json`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      
      if (response.ok) {
        const folderData = await response.json();
        
        // Update the node's data with fresh values
        Object.assign(node.data, folderData);
        
        // Update the node's title (which is just the full_path from serializer)
        node.setTitle(folderData.title);
        
        // Try different methods to trigger re-render (same as for assets)
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
      
      // Fetch fresh asset data for this folder
      const response = await fetch(`/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${parentFolderId}`, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      
      if (response.ok) {
        const assetsData = await response.json();
        
        // Update each modified asset node with fresh data
        assetsData.forEach(assetData => {
          const nodeKey = assetData.key; // Should be "a-{id}"
          const assetId = parseInt(nodeKey.replace('a-', ''), 10);
          
          // Only update if this asset was in our updated list
          if (updatedAssetIds.includes(assetId)) {
            const node = this.tree.findKey(nodeKey);
            if (node) {
              
              // Update the node's data with fresh values
              Object.assign(node.data, assetData);
              
              // Try different methods to trigger re-render
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

    _optionsFor(colId) {
    switch (colId) {
      case "migration_status":
        return this.migrationStatusOptions;
      case "aspace_collection_id":
        return this.aspaceCollectionOptions;
      case "contentdm_collection_id":
        return this.contentdmCollectionOptions;
      case "assigned_to":
        return this.userOptions;
    }
    return null;
  }

  _renderInput(colInfo, value, colId) {
    if (!colInfo.elem.dataset.rendered) {
      const input = document.createElement("input");
      input.type = "text";
      input.name = colId;
      input.value = value ?? "";
      colInfo.elem.innerHTML = "";
      colInfo.elem.appendChild(input);
      colInfo.elem.dataset.rendered = "true";
    } else {
      const input = colInfo.elem.querySelector("input");
      if (input) input.value = value ?? "";
    }
  }

  _renderCheckbox(colInfo, value, colId) {
    if (!colInfo.elem.dataset.rendered) {
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.name = colId;
      checkbox.checked = Boolean(value);
      colInfo.elem.innerHTML = "";
      colInfo.elem.appendChild(checkbox);
      colInfo.elem.dataset.rendered = "true";
    } else {
      const checkbox = colInfo.elem.querySelector("input");
      if (checkbox) checkbox.checked = Boolean(value);
    }
  }

  async _lazyLoadFolderChildren(e) {
    const node = e.node;
    if (!node?.data?.folder) return [];

    const parentId = node.data.key ?? node.data.id;
    if (!parentId) return [];

    try {
      const children = await this._fetchFolderChildren(parentId);
      node.lazy = false;
      node.data.lazy = false;

      requestAnimationFrame(() => {
        const t = node.tree;
        if (t?.updateViewport) t.updateViewport();
        else if (t?._updateViewportThrottled) t._updateViewportThrottled();
      });

      return children;
    } catch (err) {
      console.error("Folder lazy load failed:", err);
      node.lazy = false;
      node.data.lazy = false;
      return [];
    }
  }

}
