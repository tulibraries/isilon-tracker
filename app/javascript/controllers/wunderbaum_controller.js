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
  currentMatchCount = 0;
  currentNotesMatchCount = 0;
  currentMatchedKeys = new Set();
  currentFilterSignature = null;
  filterMode = "hide";
  folderCache = new Map();
  assetCache = new Map();
  fullTreeSource = [];
  hideFilterCache = null;
  dimFilterCache = null;
  dimRenderedCache = null;
  dimFilterAbortController = null;
  isFilteredTreeMode = false;
  loadedFolders = new Set();
  folderMatchCounts = new Map();

  inflightControllers = new Set();
  _filterTimer = null;
  _filterSeq = 0;
  selectInflightControllers = new Set();

  selectLikeColumns = new Set([
    "migration_status",
    "assigned_to",
    "contentdm_collection_id",
    "aspace_collection_id"
  ]);

  folderSelectLikeColumns = new Set([
    "assigned_to"
  ]);

  assetOnlySelectColumns = new Set([
    "migration_status",
    "contentdm_collection_id",
    "aspace_collection_id"
  ]);

  // Initializes option vocabularies, builds the Wunderbaum instance, and wires all UI behavior.
  async connect() {
    await Promise.all([
      this._fetchOptions(`/file_types.json?volume_id=${this.volumeIdValue}`, "fileTypeOptions"),
      this._fetchOptions("/migration_statuses.json", "migrationStatusOptions"),
      this._fetchOptions("/aspace_collections.json", "aspaceCollectionOptions"),
      this._fetchOptions("/contentdm_collections.json", "contentdmCollectionOptions"),
      this._fetchOptions("/users.json", "userOptions")
    ]);

    const selectAllButton = document.getElementById("select-all");
    new bootstrap.Tooltip(document.getElementById("select-all"));
    this._updateSelectAllButtonState();

    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      });
      const source = await res.json();
      this.fullTreeSource = Array.isArray(source) ? source : [];

      this.tree = new Wunderbaum({
        element: this.element,
        id: "tree",
        keyboard: true,
        autoActivate: true,
        checkbox: true,
        lazy: true,
        selectMode: "hier",
        columnsResizable: true,
        columnsSortable: true,
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
            sortValue: (node) => (node?.data?.migration_status || "").toString().toLowerCase()
          },
          {
            id: "assigned_to",
            classes: "wb-helper-center",
            filterable: true,
            title: "Assigned To",
            width: "175px",
            sortValue: (node) => {
              const label = node?.data?.assigned_to ||
                this._optionLabelFor("assigned_to", node?.data?.assigned_to_id);
              return (label || "").toString().toLowerCase();
            }
          },
          {
            id: "is_duplicate",
            classes: "wb-helper-center",
            filterable: true,
            title: "Is Duplicate",
            width: "150px"
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
            filterable: true,
            title: "File type",
            width: "175px"
          },
          { id: "file_size", classes: "wb-helper-center", title: "File size", width: "150px" },
          { id: "isilon_date", classes: "wb-helper-center", title: "Isilon date created", width: "175px" },
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
            width: "210px",
            html: `<input type="checkbox" tabindex="-1">`
          },
        ],

        icon: ({ node }) => {
          if (!node.data.folder) return "bi bi-files";
        },

        lazyLoad: (e) => {
          if (!e.node?.data?.folder) return [];
          if (this.isFilteredTreeMode) return [];
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
          const isProgrammaticExpand = this.expandingNodes.has(nodeKey);

          if (this.isFilteredTreeMode) return;

          if (this._hasActiveFilter()) {
            if (this.filterMode === "dim") {
              await this._ensureAssetsForFolderCancellable(
                nodeKey,
                this._filterSeq
              );
            }

            if (!isProgrammaticExpand) {
              this._reapplyFilterIfAny();
            } else if (this.filterMode === "dim") {
              this._reapplyFilterIfAny();
            }
            return;
          }

          await this._ensureAssetsForFolderCancellable(
            nodeKey,
            this._filterSeq
          );

          if (!isProgrammaticExpand || this._hasActiveFilter()) {
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
          const isFolder = node.data.folder === true;
          const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id ?? "");
          const isMatchedNode = this.currentMatchedKeys.has(nodeKey);

          node.setClass("wb-match", isMatchedNode);

          for (const colInfo of Object.values(e.renderColInfosById)) {
            const colId = colInfo.id;
            let rawValue = this._normalizeValue(
              colId,
              colId === "assigned_to" ? node.data.assigned_to_id : node.data[colId]
            );

            if (isFolder && colId !== "assigned_to" && this.selectLikeColumns.has(colId)) {
              colInfo.elem.replaceChildren();
              colInfo.elem.classList.remove("wb-select-like");
              continue;
            }

            if (colId === "is_duplicate") {
              colInfo.elem.replaceChildren();
              if (!isFolder && rawValue) {
                const tag = document.createElement("span");
                tag.className = "duplicate-tag";
                tag.textContent = "Duplicate";
                colInfo.elem.appendChild(tag);
              }
              continue;
            }

            if (colId === "aspace_linking_status" && isFolder) {
              colInfo.elem.replaceChildren();
              colInfo.elem.classList.remove("wb-select-like");
              continue;
            }

            let displayValue = rawValue ?? "";

            if (this.selectLikeColumns.has(colId)) {
              if (colId === "assigned_to" && node.data?.assigned_to) {
                displayValue = node.data.assigned_to;
                if (String(displayValue) === String(rawValue)) {
                  displayValue = this._optionLabelFor(colId, rawValue);
                }
              } else {
                displayValue = this._optionLabelFor(colId, rawValue);
              }
            }

            colInfo.elem.dataset.colid = colId;

            const isSelectLike =
              this.selectLikeColumns.has(colId) &&
              (!isFolder || colId === "assigned_to");

            if (isSelectLike && displayValue !== "") {
              colInfo.elem.classList.add("wb-select-like");
            } else {
              colInfo.elem.classList.remove("wb-select-like");
            }

            util.setValueToElem(colInfo.elem, displayValue);

            if (colId === "notes") {
              this._syncNotesHighlight(colInfo.elem, node, displayValue);
            }
          }

          const titleElem = e.nodeElem.querySelector("span.wb-title");
          if (!titleElem) return;

          if (isFolder) {
            titleElem.textContent = node.title || "";

            const totalCount = node.data?.descendant_assets_count;

            if (totalCount != null) {
              const totalBadge = document.createElement("span");
              totalBadge.className = "wb-badge";
              totalBadge.textContent = totalCount;
              totalBadge.title = `${totalCount} total assets`;
              totalBadge.style.marginLeft = "6px";
              titleElem.appendChild(totalBadge);
            }

            const folderKey = String(
              node.key ??
              node.data?.key ??
              node.data?.id
            );

            const matchCount =
              this.folderMatchCounts.get(folderKey) || 0;

            if (this._hasActiveFilter() && matchCount > 0) {
              const matchBadge = document.createElement("span");
              matchBadge.className = "wb-badge wb-match-badge";
              matchBadge.textContent = `${matchCount} matches`;
              matchBadge.title =
                `${matchCount} matching assets in this folder and its subfolders`;
              matchBadge.style.marginLeft = "6px";
              titleElem.appendChild(matchBadge);
            }
          } else {
            titleElem.innerHTML =
              `<a href="${node.data.url}" class="asset-link" target="_blank" rel="noopener" data-turbo="false">${node.title}</a>`;
          }

          this._syncTitleHighlight(titleElem, node);
        },
        
        buttonClick: (e) => {
          if (e.command === "sort") {
            const colDef = e.info.colDef;
            const dir = colDef.sortDir ?? 1;
            e.tree.sortByProperty({
              colId: e.info.colId,
              dir,
              sort: colDef.sort,
              sortValue: colDef.sortValue,
              updateColInfo: true
            });
            colDef.sortDir = dir === 1 ? -1 : 1;
          }

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

          if (colId === "assigned_to") {
            const label = this._optionLabelFor("assigned_to", value);
            e.node.data.assigned_to_id = value === "unassigned" ? null : value;
            e.node.data.assigned_to = label;
          } else {
            e.node.data[colId] = value;
          }
          this._saveCellChange(e.node, colId, value);
        },

        select: (e) => {
          const node = e.node;
          const shouldSelect = !!node?.isSelected?.();

          if (node?.data?.folder) {
            setTimeout(() => {
              void this._loadAndSelectDescendants(node, shouldSelect);
            }, 0);
            return;
          }

          this._emitSelectionChange();
          this._updateSelectAllButtonState(e.tree.getSelectedNodes().length);
        },

        source
      });

      selectAllButton.addEventListener("click", () => {
        document.getElementById("tree-match-count")?.remove();

        if (!this._hasActiveFilter()) {
          this._updateSelectAllButtonState(
            this.tree.getSelectedNodes().length
          );
          return;
        }

        const matched = [];
        const selectedKeys = new Set(
          this.tree.getSelectedNodes().map(n => n.key)
        );

        if (this.isFilteredTreeMode) {
          this.tree.visit((node) => {
            if (node.statusNodeType) return;
            matched.push(node);
          });
        } else {
          const predicate = this.currentFilterPredicate;
          if (!predicate) return;

          this.tree.visit((node) => {
            if (node.statusNodeType) return;
            if (predicate(node)) matched.push(node);
          });
        }

        const allSelected =
          matched.length > 0 &&
          matched.every(n => selectedKeys.has(n.key));

        const total = matched.length;
        const verb = allSelected ? "Clearing" : "Selecting";

        this._setLoading(true, `${verb} 0%`);

        setTimeout(async () => {
          const status = document.querySelector(".wb-loading");
          let processed = 0;
          const step = 40;

          for (const node of matched) {
            node.setSelected(!allSelected, { force: true });
            processed += 1;

            if (processed % step === 0) {
              await new Promise(requestAnimationFrame);
              if (status) {
                const percent = Math.round((processed / total) * 100);
                status.textContent = `${verb} ${percent}%`;
              }
            }
          }

          if (status) {
            status.textContent = `${verb} 100%`;
          }

          this._emitSelectionChange();
          this._updateSelectAllButtonState(
            this.tree.getSelectedNodes().length
          );

          this._setLoading(false);
        }, 0);
      });

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

      this.element.addEventListener("click", (e) => {
        const checkbox = e.target.closest?.(".wb-checkbox");
        if (!checkbox) return;
        const node = Wunderbaum.getNode(checkbox);
        if (!node?.data?.folder) return;
        const shouldSelect = !!node.isSelected?.();
        void this._loadAndSelectDescendants(node, shouldSelect);
      });

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
  }

  // Cancels pending async work and timers when the controller is removed.
  disconnect() {
    clearTimeout(this._filterTimer);
    this._cancelInflight();
    this._resetFilterCaches(null);
  }

  // Returns true when any text or column filter is active.
  _hasActiveFilter() {
    return !!(this.currentFilterPredicate || this.currentQuery || this.columnFilters.size > 0);
  }

  // Updates the select-all button visual state and tooltip.
  _updateSelectAllButtonState(selectedCount = null) {
    const btn = document.getElementById("select-all");
    if (!btn) return;

    const selected = selectedCount ?? (this.tree ? this.tree.getSelectedNodes().length : 0);
    const hasActiveFilter = this._hasActiveFilter();
    const isChecked = selected > 0;
    const isInactive = !hasActiveFilter && !isChecked;

    btn.classList.toggle("is-checked", isChecked);
    btn.classList.toggle("is-inactive", isInactive);
    btn.setAttribute("aria-disabled", String(isInactive));

    btn.title = isChecked
      ? "Clear selection"
      : hasActiveFilter
        ? "Select filtered items"
        : "Select all filtered results";
  }

  // Reapply the current filter with stored options.
  _reapplyFilterIfAny() {
    if (this.isFilteredTreeMode) {
      this._updateSelectAllButtonState();
      return;
    }
    if (!this.currentFilterPredicate) return;
    const opts = { ...(this.currentFilterOpts || {}), mode: this.filterMode };
    this.currentFilterOpts = opts;
    this.tree.filterNodes(this.currentFilterPredicate, opts);
    this._updateSelectAllButtonState();
  }

  _syncMatchedNodeClasses() {
    const matchedKeys = this.currentMatchedKeys;
    this.tree?.visit?.((node) => {
      if (node.statusNodeType) return;
      const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id ?? "");
      node.setClass("wb-match", matchedKeys.has(nodeKey));
    });
  }

  // Executes backend-backed filtering and materializes matching paths.
  async _runDeepFilter(raw, options = {}) {
    this._cancelActiveSearch();
    this._cancelInflight();

    const mySeq = ++this._filterSeq;

    this.loadedFolders.clear();
    this.assetsLoadedFor.clear();
    this.assetCache.clear();
    this.folderMatchCounts.clear();

    const q = (raw || "").trim().toLowerCase();
    this.currentQuery = q;

    const hasColumnFilters = this.columnFilters.size > 0;

    if (!q && !hasColumnFilters) {
      this.currentFilterPredicate = null;
      this.currentFilterOpts = null;
      this.tree.clearFilter();

      document.getElementById("tree-match-count")?.remove();

      this._setLoading(false);
      this._updateFilterModeButton();
      this._updateSelectAllButtonState();

      return;
    }

    this._showMatchCountStatus("Searching…");
    this._setLoading(true, "Searching…");

    await new Promise(requestAnimationFrame);

    const params = new URLSearchParams();

    if (q) {
      params.set("q", q);
    }

    for (const [col, val] of this.columnFilters.entries()) {
      if (val !== "") {
        params.set(col, val);
      }
    }

    const cachedPayload = options.payload || null;
    const searchCtrl = cachedPayload ? null : this._beginFetchGroup();

    try {
      let payload = cachedPayload;

      if (!payload) {
        const [folderResponse, assetResponse] = await Promise.all([
          this._fetchJson(
            `/volumes/${this.volumeIdValue}/file_tree_folders_search.json?${params.toString()}`,
            searchCtrl
          ).catch(() => []),

          this._fetchJson(
            `/volumes/${this.volumeIdValue}/file_tree_assets_search.json?${params.toString()}`,
            searchCtrl
          ).catch(() => ({
            results: [],
            total_count: 0,
            notes_match_count: 0
          }))
        ]);

        payload = this._normalizeDimSearchPayload(folderResponse, assetResponse, q);
      }

      if (mySeq !== this._filterSeq) {
        return;
      }

      const hidePayload =
        options.signature &&
        this.hideFilterCache?.signature === options.signature
          ? this.hideFilterCache.payload
          : null;

      const folders = Array.isArray(hidePayload?.folders) ? hidePayload.folders : payload.folders;
      const assets = payload.assets;
      const backendMatchCount = Number(payload?.totalCount);
      const backendNotesMatchCount = Number(payload?.notesMatchCount);
      const matchedKeys = Array.isArray(hidePayload?.matched_keys)
        ? hidePayload.matched_keys
        : Array.isArray(payload.matchedKeys)
          ? payload.matchedKeys
          : [];
      const hidePayloadCount = Number(hidePayload?.total_count);
      const hidePayloadNotesMatchCount = Number(hidePayload?.notes_match_count);
      const resolvedMatchCount = Number.isFinite(hidePayloadCount)
        ? hidePayloadCount
        : Number.isFinite(backendMatchCount)
          ? backendMatchCount
          : matchedKeys.length;
      const resolvedNotesMatchCount = Number.isFinite(hidePayloadNotesMatchCount)
        ? hidePayloadNotesMatchCount
        : Number.isFinite(backendNotesMatchCount)
          ? backendNotesMatchCount
          : 0;

      this.currentMatchedKeys = new Set(matchedKeys.map(String));
      this._updateMatchCount(resolvedMatchCount, resolvedNotesMatchCount);

      if (!q && this.columnFilters.size > 0) {
        await this._materializeColumnFilterResults(
          folders,
          assets,
          mySeq
        );
      } else {
        await this._materializeSearchResults(
          folders,
          assets,
          mySeq
        );
      }

      if (this.filterMode === "dim") {
        await this._loadDimVisibleAssets(folders, assets, mySeq);
        this._sortLiveTreeNodes();
      }

      if (mySeq !== this._filterSeq) {
        return;
      }

      this._applyPredicate(q);
      this._syncMatchedNodeClasses();
      this._updateMatchCount(resolvedMatchCount, resolvedNotesMatchCount);
      if (this.filterMode === "dim" && options.signature) {
        this.dimRenderedCache = this._captureDimRenderedCache(
          options.signature,
          resolvedMatchCount,
          resolvedNotesMatchCount
        );
      }
    } finally {
      if (searchCtrl) {
        this.inflightControllers.delete(searchCtrl);
      }
      this._setLoading(false);
    }
  }

  _normalizeDimSearchPayload(folderResponse, assetResponse, q) {
    let folders = [];
    let folderTotalCount = 0;
    let folderNotesMatchCount = 0;

    if (Array.isArray(folderResponse)) {
      folders = folderResponse;
      folderTotalCount = folders.length;
    } else if (Array.isArray(folderResponse?.results)) {
      folders = folderResponse.results;
      folderTotalCount = Number(folderResponse.total_count ?? folders.length);
      folderNotesMatchCount = Number(folderResponse.notes_match_count ?? 0);
    }

    let assets = [];

    if (Array.isArray(assetResponse)) {
      assets = assetResponse;
    } else if (Array.isArray(assetResponse?.results)) {
      assets = assetResponse.results;
    }

    this._buildFolderMatchCounts(assets);
    const folderMatchCount = Number.isFinite(folderTotalCount) ? folderTotalCount : folders.length;

    let backendAssetCount = assets.length;
    let backendNotesMatchCount = 0;

    if (!Array.isArray(assetResponse) && assetResponse?.total_count != null) {
      backendAssetCount = Number(assetResponse.total_count);
      backendNotesMatchCount = Number(assetResponse.notes_match_count ?? 0);
    }

    if (!Number.isFinite(backendAssetCount)) {
      backendAssetCount = assets.length;
    }

    if (!Number.isFinite(folderNotesMatchCount)) {
      folderNotesMatchCount = 0;
    }

    if (!Number.isFinite(backendNotesMatchCount)) {
      backendNotesMatchCount = 0;
    }

    const hasFolderCapableFilters =
      q.length > 0 ||
      (this.columnFilters.has("assigned_to") &&
        String(this.columnFilters.get("assigned_to") ?? "") !== "");
    const totalNotesMatchCount = folderNotesMatchCount + backendNotesMatchCount;

    return {
      folders,
      assets,
      matchedKeys: [
        ...folders.map((folder) => String(folder.key ?? folder.id)),
        ...assets.map((asset) => String(asset.key ?? `a-${asset.id}`))
      ],
      totalCount: hasFolderCapableFilters ? folderMatchCount + backendAssetCount : backendAssetCount,
      notesMatchCount: totalNotesMatchCount
    };
  }

  async _loadDimVisibleAssets(folders, assets, seq) {
    const folderIds = new Set();

    for (const folder of folders) {
      if (folder?.id != null) {
        folderIds.add(String(folder.id));
      }
      if (Array.isArray(folder?.path)) {
        folder.path.forEach((id) => {
          if (id != null) folderIds.add(String(id));
        });
      }
    }

    for (const asset of assets) {
      const parentId = asset?.parent_folder_id ?? asset?.folder_id;
      if (parentId != null) {
        folderIds.add(String(parentId));
      }
      if (Array.isArray(asset?.path)) {
        asset.path.forEach((id) => {
          if (id != null) folderIds.add(String(id));
        });
      }
    }

    if (!folderIds.size) return;
    const orderedFolderIds = [ ...folderIds ];
    await this._ensureAssetsForFoldersBatch(orderedFolderIds, seq);

    for (const folderId of orderedFolderIds) {
      if (seq !== this._filterSeq) return;
      this._expandNodeByKey(folderId);
    }
  }

  // Applies the current filter predicate to the tree.
  _applyPredicate(q) {
    if (this.isFilteredTreeMode && this.currentMatchedKeys.size > 0) {
      const matchedKeys = new Set(this.currentMatchedKeys);
      const predicate = (node) => {
        const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id ?? "");
        return matchedKeys.has(nodeKey);
      };

      const opts = {
        autoExpand: true,
        leavesOnly: false,
        matchBranch: this.filterMode === "hide",
        mode: this.filterMode
      };

      this.currentFilterPredicate = predicate;
      this.currentFilterOpts = opts;

      this.tree.filterNodes(predicate, opts);
      this._updateSelectAllButtonState();
      return;
    }

    const predicate = (node) => {
      if (q) {
        const text = String(
          node.data.full_path ??
          node.data.title ??
          node.data.name ??
          node.title ??
          ""
        ).toLowerCase();

        const notes = String(node.data.notes ?? "").toLowerCase();

        if (!text.includes(q) && !notes.includes(q)) return false;
      }

      for (const [colId, val] of this.columnFilters.entries()) {
        const normalizedValue = this._filterValueFor(colId, node.data);
        const normalizedStr =
          normalizedValue == null
            ? ""
            : String(normalizedValue).toLowerCase();

        const filterStr = String(val ?? "").toLowerCase();

        if (normalizedStr !== filterStr) return false;
      }

      return true;
    };

    const opts = {
      leavesOnly: false,
      matchBranch: false,
      mode: this.filterMode
    };

    this.currentFilterPredicate = predicate;
    this.currentFilterOpts = opts;

    this.tree.filterNodes(predicate, opts);

    this._updateFilterModeButton();
    this._updateSelectAllButtonState();
  }

  // Load and select all descendants for a folder node without blocking UI.
  async _loadAndSelectDescendants(node, flag) {
    if (!node?.data?.folder) return;

    const filterSeq = this._filterSeq;
    const queue = [node];
    let processed = 0;

    this._setLoading(true, "Selecting…");

    try {
      while (queue.length > 0) {
        if (filterSeq !== this._filterSeq) {
          break;
        }

        const current = queue.shift();
        const key = String(current.key ?? current.data?.key ?? current.data?.id ?? "");
        if (!key) continue;

        if (!this.isFilteredTreeMode) {
          await this._hydrateSingleParentByKey(key, filterSeq);

          if (
            filterSeq !== this._filterSeq) {
            break;
          }

          await this._ensureAssetsForFolderCancellable(key, filterSeq);

          if (
            filterSeq !== this._filterSeq) {
            break;
          }
        }

        const children = current.children || [];
        for (const child of children) {
          if (
            filterSeq !== this._filterSeq) {
            break;
          }

          if (child.statusNodeType) continue;

          child.setSelected(flag, { force: true });

          if (child.data?.folder) {
            queue.push(child);
          }
        }

        processed += 1;
        if ((processed & 127) === 0) {
          await Promise.resolve();
        }
      }
    } finally {
      if (
        filterSeq === this._filterSeq) {
        this._emitSelectionChange();
        this._updateSelectAllButtonState();
      }

      this._setLoading(false);
    }
  }

  // Finds a tree node by its key.
  _findNodeByKey(key) {
    const skey = String(key);
    return this.tree?.findKey?.(skey) ?? null;
  }

  buildFilterRequest(raw = this.currentQuery) {
    const request = this.getFilterRequestParams(raw);
    const signature = request.params?.toString() || null;

    if (this.currentFilterSignature !== signature) {
      this._resetFilterCaches(signature);
    }

    this._cancelActiveSearch();
    this._cancelInflight();

    const seq = ++this._filterSeq;

    this.loadedFolders.clear();
    this.assetsLoadedFor.clear();
    this.assetCache.clear();
    this.folderMatchCounts.clear();
    this.currentMatchedKeys = new Set();
    this.currentQuery = request.query;

    if (request.empty) {
      return { seq, query: request.query, params: null, signature, empty: true };
    }

    this._showMatchCountStatus("Searching…");
    this._setLoading(true, "Searching…");
    this._enterPendingHideFilter(seq);

    return { seq, query: request.query, params: request.params, signature, empty: false };
  }

  getFilterRequestParams(raw = this.currentQuery) {
    const q = (raw || "").trim().toLowerCase();
    const hasColumnFilters = this.columnFilters.size > 0;

    if (!q && !hasColumnFilters) {
      return { query: q, params: null, empty: true };
    }

    const params = new URLSearchParams();
    if (q) {
      params.set("q", q);
    }

    for (const [col, val] of this.columnFilters.entries()) {
      if (val !== "") {
        params.set(col, val);
      }
    }

    return { query: q, params, empty: false };
  }

  async applyFilterResults(payload, seq) {
    if (seq !== this._filterSeq) return;

    const folders = Array.isArray(payload?.folders) ? payload.folders : [];
    const assets = Array.isArray(payload?.assets) ? payload.assets : [];
    const matchedKeys = Array.isArray(payload?.matched_keys)
      ? payload.matched_keys.map(String)
      : [];

    this._buildFolderMatchCounts(assets);
    this.currentMatchedKeys = new Set(matchedKeys);
    this.isFilteredTreeMode = true;
    this.currentFilterPredicate = null;
    this.currentFilterOpts = null;
    this.tree?.clearFilter?.();

    await this._renderFilteredTree(folders, assets, seq);

    if (seq !== this._filterSeq) return;

    this._syncMatchedNodeClasses();
    this._updateMatchCount(
      Number(payload?.total_count) || matchedKeys.length,
      Number(payload?.notes_match_count) || 0
    );
    this._updateSelectAllButtonState();
  }

  finalizeFilterRequest(seq) {
    if (seq !== this._filterSeq) return;
    this._setLoading(false);
  }

  _enterPendingHideFilter(seq) {
    if (seq !== this._filterSeq) return;

    this.isFilteredTreeMode = true;
    this.currentFilterPredicate = null;
    this.currentFilterOpts = null;
    this.tree?.clearFilter?.();
    this._replaceTreeContents([]);
    this._updateSelectAllButtonState(0);
  }

  async _abortPendingHideFilter(seq) {
    if (seq !== this._filterSeq) return;

    this.isFilteredTreeMode = false;
    this.currentMatchedKeys = new Set();
    this.currentFilterPredicate = null;
    this.currentFilterOpts = null;
    this.tree?.clearFilter?.();
    await this._restoreFullTree();
    this._syncMatchedNodeClasses();
    this._updateSelectAllButtonState(0);
  }

  async clearAllFilters() {
    this._cancelActiveSearch();
    this._cancelInflight();

    document.getElementById("tree-match-count")?.remove();
    this.columnFilters.clear();
    this.currentFilterPredicate = null;
    this.currentFilterOpts = null;
    this.currentQuery = "";
    this.currentFilterSignature = null;
    this.currentMatchedKeys = new Set();
    this.isFilteredTreeMode = false;
    this._resetFilterCaches(null);
    this.loadedFolders.clear();
    this.assetsLoadedFor.clear();
    this.assetCache.clear();
    this.folderMatchCounts.clear();

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

    if (this.tree) {
      this.tree.selectAll(false);
      this.tree.clearFilter();
    }

    await this._restoreFullTree();
    this._syncMatchedNodeClasses();

    this._emitSelectionChange();
    this.columnValueCache.clear();
    this._setLoading(false);
    this._updateFilterModeButton();
    this._updateSelectAllButtonState(0);
  }

  toggleFilterMode() {
    if (
      this.filterMode === "dim" &&
      this.currentFilterSignature &&
      this._hasActiveFilter()
    ) {
      this.dimRenderedCache = this._captureDimRenderedCache(
        this.currentFilterSignature,
        this.currentMatchCount,
        this.currentNotesMatchCount
      );
    }

    this.filterMode = this.filterMode === "hide" ? "dim" : "hide";
    if (this.tree?.options?.filter) {
      this.tree.options.filter.mode = this.filterMode;
    }
    if (this.currentFilterOpts) {
      this.currentFilterOpts.mode = this.filterMode;
    }
    this._updateFilterModeButton();
    return this.filterMode;
  }

  getFilterMode() {
    return this.filterMode;
  }

  canToggleFilterMode() {
    return true;
  }

  hasCachedHideFilter(signature = this.currentFilterSignature) {
    return !!(signature && this.hideFilterCache?.signature === signature && this.hideFilterCache?.payload);
  }

  cacheHideFilterResults(signature, payload) {
    if (!signature || !payload) return;
    this.hideFilterCache = { signature, payload };
  }

  async applyCachedHideFilter(signature = this.currentFilterSignature) {
    if (!this.hasCachedHideFilter(signature)) return false;

    const seq = ++this._filterSeq;
    this.currentFilterSignature = signature;
    await this.applyFilterResults(this.hideFilterCache.payload, seq);
    this.finalizeFilterRequest(seq);
    return true;
  }

  prefetchDimFilter(raw = this.currentQuery, signature = this.currentFilterSignature) {
    if (!signature) return Promise.resolve(null);
    if (this.dimFilterCache?.signature === signature) {
      if (this.dimFilterCache.payload) return Promise.resolve(this.dimFilterCache.payload);
      if (this.dimFilterCache.promise) return this.dimFilterCache.promise;
    }

    if (this.dimFilterAbortController) {
      try { this.dimFilterAbortController.abort(); } catch {}
    }

    const request = this.getFilterRequestParams(raw);
    if (request.empty || !request.params) return Promise.resolve(null);

    const ctrl = new AbortController();
    this.dimFilterAbortController = ctrl;

    const promise = Promise.all([
      this._fetchJson(
        `/volumes/${this.volumeIdValue}/file_tree_folders_search.json?${request.params.toString()}`,
        ctrl
      ).catch(() => []),
      this._fetchJson(
        `/volumes/${this.volumeIdValue}/file_tree_assets_search.json?${request.params.toString()}`,
        ctrl
      ).catch(() => ({
        results: [],
        total_count: 0
      }))
    ]).then(([folderResponse, assetResponse]) => {
      if (ctrl.signal.aborted) return null;

      const payload = this._normalizeDimSearchPayload(folderResponse, assetResponse, request.query);
      if (this.currentFilterSignature === signature) {
        this.dimFilterCache = { signature, payload, promise: null };
      }
      return payload;
    }).catch((error) => {
      if (ctrl.signal.aborted) return null;
      console.error("Failed to prefetch dim filter results", error);
      return null;
    }).finally(() => {
      if (this.dimFilterAbortController === ctrl) {
        this.dimFilterAbortController = null;
      }
      if (this.dimFilterCache?.signature === signature && this.dimFilterCache?.promise === promise) {
        this.dimFilterCache.promise = null;
      }
    });

    this.dimFilterCache = { signature, payload: null, promise };
    return promise;
  }

  async applyDimFilter(raw = this.currentQuery, signature = this.currentFilterSignature) {
    const request = this.getFilterRequestParams(raw);
    const effectiveSignature = signature || request.params?.toString() || null;
    this.currentQuery = request.query;
    this.currentFilterSignature = effectiveSignature;
    this.currentMatchedKeys = new Set();
    this.currentFilterPredicate = null;
    this.currentFilterOpts = null;

    if (
      effectiveSignature &&
      this.dimRenderedCache?.signature === effectiveSignature &&
      this.dimRenderedCache?.nodes
    ) {
      this.isFilteredTreeMode = false;
      this._restoreDimRenderedCache(this.dimRenderedCache);
      return;
    }

    if (this.isFilteredTreeMode) {
      this.isFilteredTreeMode = false;
      this.tree?.clearFilter?.();
      await this._restoreFullTree();
    }

    let payload = null;
    if (effectiveSignature && this.dimFilterCache?.signature === effectiveSignature) {
      payload = this.dimFilterCache.payload || null;
    }

    if (!payload && this.dimFilterAbortController) {
      try { this.dimFilterAbortController.abort(); } catch {}
      this.dimFilterAbortController = null;
      if (this.dimFilterCache?.signature === effectiveSignature) {
        this.dimFilterCache.promise = null;
      }
    }

    await this._runDeepFilter(raw, payload ? { payload, signature: effectiveSignature } : { signature: effectiveSignature });
  }

  _resetFilterCaches(signature) {
    if (this.dimFilterAbortController) {
      try { this.dimFilterAbortController.abort(); } catch {}
    }
    this.dimFilterAbortController = null;
    this.currentFilterSignature = signature;
    this.hideFilterCache = null;
    this.dimFilterCache = null;
    this.dimRenderedCache = null;
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
    btn.disabled = false;
    btn.setAttribute("title", isHideMode ? "Hide unmatched nodes" : "Dim unmatched nodes");

    if (icon) {
      icon.classList.remove("bi-filter-square", "bi-filter-square-fill");
      icon.classList.add(isHideMode ? "bi-filter-square-fill" : "bi-filter-square");
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
      this._sortTreeItemsArray(childFolders);
      this.folderCache.set(pid, childFolders);
    }

    const existing = new Set((parentNode.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
    const toAdd = childFolders.filter((folder) => !existing.has(String(folder.key ?? folder.id)));
    if (toAdd.length) parentNode.addChildren?.(toAdd);
    if (!toAdd.length && childFolders.length === 0 && parentNode.children == null) {
      parentNode.children = [];
    }

    this.loadedFolders.add(pid);
  }

  async _hydrateParentsBatch(parentKeys, mySeq) {
    if (mySeq !== this._filterSeq) return;

    const parentIds = [...new Set(parentKeys.map(String))]
      .filter((pid) => pid && !this.loadedFolders.has(pid));

    if (!parentIds.length) return;

    const params = new URLSearchParams();
    parentIds.forEach((pid) => params.append("parent_ids[]", pid));

    const ctrl = this._beginFetchGroup();
    let childFolders = [];
    try {
      childFolders = await this._fetchJson(
        `/volumes/${this.volumeIdValue}/file_tree_folders.json?${params.toString()}`,
        ctrl
      ).catch(() => []);
    } finally {
      this.inflightControllers.delete(ctrl);
    }

    if (!Array.isArray(childFolders)) childFolders = [];
    this._sortTreeItemsArray(childFolders);

    const grouped = childFolders.reduce((acc, folder) => {
      const pid = String(folder.parent_folder_id ?? "");
      if (!pid) return acc;
      (acc[pid] ||= []).push(folder);
      return acc;
    }, {});

    parentIds.forEach((pid) => {
      const parentNode = this._findNodeByKey(pid);
      if (!parentNode) return;

      const children = grouped[pid] || [];
      const existing = new Set((parentNode.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
      const toAdd = children.filter((folder) => !existing.has(String(folder.key ?? folder.id)));
      if (toAdd.length) parentNode.addChildren?.(toAdd);
      if (!toAdd.length && children.length === 0 && parentNode.children == null) {
        parentNode.children = [];
      }

      this.folderCache.set(pid, children);
      this.loadedFolders.add(pid);
    });
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
      this._sortTreeItemsArray(assets);
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

  async _ensureAssetsForFoldersBatch(folderKeys, mySeq) {
    if (mySeq !== this._filterSeq) return;

    const folderIds = [...new Set(folderKeys.map(String))]
      .filter((pid) => pid && !this.assetsLoadedFor.has(pid));

    if (!folderIds.length) return;

    const params = new URLSearchParams();
    folderIds.forEach((pid) => params.append("parent_ids[]", pid));

    const ctrl = this._beginFetchGroup();
    let assets = [];
    try {
      assets = await this._fetchJson(
        `/volumes/${this.volumeIdValue}/file_tree_assets.json?${params.toString()}`,
        ctrl
      ).catch(() => []);
    } finally {
      this.inflightControllers.delete(ctrl);
    }

    if (!Array.isArray(assets)) assets = [];
    this._sortTreeItemsArray(assets);

    const grouped = assets.reduce((acc, asset) => {
      const pid = String(asset.parent_folder_id ?? "");
      if (!pid) return acc;
      (acc[pid] ||= []).push(asset);
      return acc;
    }, {});

    folderIds.forEach((pid) => {
      const node = this._findNodeByKey(pid);
      if (!node || node.data?.folder !== true) return;

      const children = grouped[pid] || [];
      const existing = new Set((node.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
      const toAdd = children.filter((asset) => !existing.has(String(asset.key ?? asset.id)));
      if (toAdd.length) node.addChildren?.(toAdd);

      this.assetCache.set(pid, children);
      this.assetsLoadedFor.add(pid);
    });
  }

  // Ensures all folder paths needed for search results exist.
  async _materializeSearchResults(folders, assets, seq) {
    const paths = new Set();
    const assetParentIds = new Set();

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
          assetParentIds.add(String(pid));
        }
      }
    }

    for (const path of paths) {
      if (seq !== this._filterSeq) return;
      await this._loadPath(path.split(">"), seq);
    }

    for (const pid of assetParentIds) {
      if (seq !== this._filterSeq) return;
      await this._ensureAssetsForFolderCancellable(pid, seq);
    }
  }

  async _materializeColumnFilterResults(folders, assets, seq) {
    const assetParentIds = new Set();
    const matchedFolderIds = new Set();
    const pathArrays = [];

    for (const folder of folders) {
      if (Array.isArray(folder.path)) {
        pathArrays.push([...folder.path, folder.id].map(String));
      }
      if (folder?.id != null) {
        matchedFolderIds.add(String(folder.id));
      }
    }

    for (const asset of assets) {
      if (Array.isArray(asset.path)) {
        const pid = asset.parent_folder_id ?? asset.folder_id;
        if (pid != null) {
          pathArrays.push([...asset.path, pid].map(String));
          assetParentIds.add(String(pid));
        }
      }
    }

    const maxDepth = pathArrays.reduce((max, path) => Math.max(max, path.length), 0);

    for (let depth = 0; depth < maxDepth - 1; depth += 1) {
      if (seq !== this._filterSeq) return;

      const parentIds = [...new Set(
        pathArrays
          .filter((path) => path.length > depth + 1)
          .map((path) => path[depth])
      )];

      await this._hydrateParentsBatch(parentIds, seq);

      for (const pid of parentIds) {
        const node = this._findNodeByKey(pid);
        if (!node) continue;

        const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id);
        if (node.expanded || this.expandingNodes.has(nodeKey)) continue;

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

    if (seq !== this._filterSeq) return;
    await this._appendMatchedAssets(assets, seq);

    for (const folderId of matchedFolderIds) {
      if (seq !== this._filterSeq) return;
      this._expandNodeByKey(folderId);
    }

    for (const pid of assetParentIds) {
      if (seq !== this._filterSeq) return;
      this._expandNodeByKey(pid);
    }
  }

  async _mergeFilterResults(folders, assets, seq) {
    const sortedFolders = [...folders].sort((left, right) => {
      const leftDepth = Array.isArray(left.path) ? left.path.length : 0;
      const rightDepth = Array.isArray(right.path) ? right.path.length : 0;

      if (leftDepth !== rightDepth) return leftDepth - rightDepth;

      return String(left.full_path ?? left.title ?? "").localeCompare(
        String(right.full_path ?? right.title ?? "")
      );
    });

    await this._mergeFolders(sortedFolders, seq);

    if (seq !== this._filterSeq) return;
    await this._appendMatchedAssets(assets, seq);
  }

  async _renderFilteredTree(folders, assets, seq) {
    const nodes = this._buildFilteredTreeData(folders, assets);
    if (seq !== this._filterSeq) return;

    this._replaceTreeContents(nodes);
    await this._expandAllFilteredFolders(seq);
  }

  _buildFilteredTreeData(folders, assets) {
    const folderNodes = new Map();

    const sortedFolders = [...folders].sort((left, right) => {
      const leftDepth = Array.isArray(left.path) ? left.path.length : 0;
      const rightDepth = Array.isArray(right.path) ? right.path.length : 0;

      if (leftDepth !== rightDepth) return leftDepth - rightDepth;

      return String(left.full_path ?? left.title ?? "").localeCompare(
        String(right.full_path ?? right.title ?? "")
      );
    });

    sortedFolders.forEach((folder) => {
      folderNodes.set(String(folder.key ?? folder.id), {
        ...folder,
        lazy: false,
        children: []
      });
    });

    const roots = [];

    sortedFolders.forEach((folder) => {
      const key = String(folder.key ?? folder.id);
      const node = folderNodes.get(key);
      const parentId = folder.parent_folder_id == null ? null : String(folder.parent_folder_id);

      if (parentId == null) {
        roots.push(node);
        return;
      }

      const parent = folderNodes.get(parentId);
      if (parent) {
        parent.children.push(node);
      }
    });

    assets.forEach((asset) => {
      const parent = folderNodes.get(String(asset.parent_folder_id ?? ""));
      if (parent) {
        parent.children.push({ ...asset, lazy: false });
      }
    });

    this._sortFilteredChildren(roots);
    return roots;
  }

  _sortFilteredChildren(nodes) {
    nodes.forEach((node) => {
      if (!Array.isArray(node.children) || node.children.length === 0) return;

      this._sortTreeItemsArray(node.children);

      this._sortFilteredChildren(node.children.filter((child) => child.folder));
    });
  }

  _compareTreeItems(left, right) {
    const leftFolder = left.folder ?? left.data?.folder;
    const rightFolder = right.folder ?? right.data?.folder;

    if (leftFolder !== rightFolder) return leftFolder ? -1 : 1;

    return String(left.title ?? left.full_path ?? left.data?.title ?? left.data?.full_path ?? "").localeCompare(
      String(right.title ?? right.full_path ?? right.data?.title ?? right.data?.full_path ?? "")
    );
  }

  _sortTreeItemsArray(items) {
    if (!Array.isArray(items) || items.length < 2) return items;
    items.sort((left, right) => this._compareTreeItems(left, right));
    return items;
  }

  _sortLiveTreeNodes() {
    const sortNodeChildren = (node) => {
      if (!Array.isArray(node?.children) || node.children.length === 0) return;

      this._sortTreeItemsArray(node.children);
      node.children.forEach((child) => {
        if (child.data?.folder) {
          sortNodeChildren(child);
        }
      });
    };

    const root = this.tree?.root;
    if (!root) return;

    sortNodeChildren(root);

    try {
      if (this.tree?.update) {
        this.tree.update();
      } else if (this.tree?.redraw) {
        this.tree.redraw();
      }
    } catch (error) {
      console.error("Failed to re-sort live tree nodes", error);
    }
  }

  _replaceTreeContents(nodes) {
    const rootNode = this.tree?.root;
    if (!rootNode) return;

    if (typeof rootNode.removeChildren === "function") {
      rootNode.removeChildren();
    } else {
      for (const child of [ ...(rootNode.children || []) ]) {
        child.remove?.();
      }
    }

    if (nodes.length) {
      rootNode.addChildren?.(nodes);
    }
  }

  _captureDimRenderedCache(signature, matchCount, notesMatchCount = 0) {
    const rootChildren = this.tree?.root?.children || [];

    return {
      signature,
      count: matchCount,
      notesMatchCount,
      matchedKeys: [ ...this.currentMatchedKeys ],
      loadedFolders: [ ...this.loadedFolders ],
      assetsLoadedFor: [ ...this.assetsLoadedFor ],
      expandedKeys: this._captureExpandedKeys(),
      nodes: rootChildren
        .filter((node) => !node.statusNodeType)
        .map((node) => this._snapshotTreeNode(node))
    };
  }

  _captureExpandedKeys() {
    const keys = [];

    this.tree?.visit?.((node) => {
      if (node.statusNodeType || !node.expanded) return;
      const key = String(node.key ?? node.data?.key ?? node.data?.id ?? "");
      if (key) keys.push(key);
    });

    return keys;
  }

  _snapshotTreeNode(node) {
    const data = {
      ...(node.data || {}),
      key: String(node.key ?? node.data?.key ?? node.data?.id ?? ""),
      title: node.title
    };

    if (node.data?.folder) {
      data.lazy = false;
    }

    const children = (node.children || [])
      .filter((child) => !child.statusNodeType)
      .map((child) => this._snapshotTreeNode(child));

    if (children.length > 0 || node.data?.folder) {
      data.children = children;
    }

    return data;
  }

  _cloneCachedNode(node) {
    const copy = { ...node };
    if (Array.isArray(node.path)) {
      copy.path = [ ...node.path ];
    }
    if (Array.isArray(node.children)) {
      copy.children = node.children.map((child) => this._cloneCachedNode(child));
    }
    return copy;
  }

  _restoreDimRenderedCache(cache) {
    const nodes = (cache.nodes || []).map((node) => this._cloneCachedNode(node));

    this.loadedFolders = new Set(cache.loadedFolders || []);
    this.assetsLoadedFor = new Set(cache.assetsLoadedFor || []);
    this.currentMatchedKeys = new Set((cache.matchedKeys || []).map(String));

    this.tree?.clearFilter?.();
    this._replaceTreeContents(nodes);

    for (const key of cache.expandedKeys || []) {
      this._expandNodeByKey(key);
    }

    this._applyPredicate(this.currentQuery);
    this._syncMatchedNodeClasses();
    this._updateMatchCount(cache.count || 0, cache.notesMatchCount || 0);
    this._updateSelectAllButtonState();
    this._setLoading(false);
  }

  async _expandAllFilteredFolders(seq) {
    const folders = [];

    this.tree?.visit?.((node) => {
      if (node.statusNodeType) return;
      if (node.data?.folder && (node.children || []).length > 0) {
        folders.push(node);
      }
    });

    let index = 0;
    for (const node of folders) {
      if (seq !== this._filterSeq) return;
      if (!node.expanded) {
        node.setExpanded(true);
      }
      index += 1;
      if ((index & 63) === 0) {
        await new Promise(requestAnimationFrame);
      }
    }
  }

  async _restoreFullTree() {
    const nodes = this.fullTreeSource.map((node) => ({ ...node }));
    this._replaceTreeContents(nodes);
  }

  async _mergeFolders(folders, seq) {
    const rootNodes = [];
    const pendingByParent = new Map();
    let processed = 0;

    for (const folder of folders) {
      if (seq !== this._filterSeq) return;

      const key = String(folder.key ?? folder.id);
      const existingNode = this._findNodeByKey(key);

      if (existingNode) {
        Object.assign(existingNode.data, folder);
        if (folder.title) {
          existingNode.setTitle(folder.title);
        }
        continue;
      }

      const parentId = folder.parent_folder_id == null ? null : String(folder.parent_folder_id);
      if (parentId == null) {
        rootNodes.push(folder);
        processed += 1;
        continue;
      }

      if (!pendingByParent.has(parentId)) {
        pendingByParent.set(parentId, []);
      }
      pendingByParent.get(parentId).push(folder);

      processed += 1;
      if ((processed & 255) === 0) {
        await new Promise(requestAnimationFrame);
      }
    }

    if (rootNodes.length) {
      const existingRootKeys = new Set(
        (this.tree?.root?.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id))
      );
      const toAdd = rootNodes.filter((folder) => !existingRootKeys.has(String(folder.key ?? folder.id)));
      if (toAdd.length) {
        this.tree?.root?.addChildren?.(toAdd);
      }
    }

    let parentIndex = 0;
    for (const [parentId, children] of pendingByParent.entries()) {
      if (seq !== this._filterSeq) return;

      const parentNode = this._findNodeByKey(parentId);
      if (!parentNode) continue;

      const childKeys = new Set(
        (parentNode.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id))
      );
      const toAdd = children.filter((folder) => !childKeys.has(String(folder.key ?? folder.id)));

      if (toAdd.length) {
        parentNode.addChildren?.(toAdd);
      }

      parentIndex += 1;
      if ((parentIndex & 63) === 0) {
        await new Promise(requestAnimationFrame);
      }
    }
  }

  async _appendMatchedAssets(assets, seq = this._filterSeq) {
    const grouped = assets.reduce((acc, asset) => {
      const pid = String(asset.parent_folder_id ?? asset.folder_id ?? "");
      if (!pid) return acc;
      (acc[pid] ||= []).push(asset);
      return acc;
    }, {});

    let parentIndex = 0;

    for (const [ pid, children ] of Object.entries(grouped)) {
      if (seq !== this._filterSeq) return;

      const node = this._findNodeByKey(pid);
      if (!node || node.data?.folder !== true) continue;

      const existing = new Set(
        (node.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id))
      );
      const toAdd = children.filter((asset) => !existing.has(String(asset.key ?? asset.id)));
      if (toAdd.length) node.addChildren?.(toAdd);

      this.assetCache.set(pid, children);
      this.assetsLoadedFor.add(pid);

      parentIndex += 1;
      if ((parentIndex & 63) === 0) {
        await new Promise(requestAnimationFrame);
      }
    }
  }

  _expandNodeByKey(key) {
    const node = this._findNodeByKey(key);
    if (!node) return;

    const nodeKey = String(node.key ?? node.data?.key ?? node.data?.id);
    if (node.expanded || this.expandingNodes.has(nodeKey)) return;

    this.expandingNodes.add(nodeKey);
    try {
      node.setExpanded(true);
    } finally {
      Promise.resolve().then(() => {
        this.expandingNodes.delete(nodeKey);
      });
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

  // Normalizes column values for predicate comparisons.
  _filterValueFor(colId, data = {}) {
    if (colId === "assigned_to") {
      const id = data.assigned_to_id;
      return (id == null || id === "") ? "unassigned" : String(id);
    }

    if (colId === "migration_status") {
      const id = data.migration_status_id ?? data.migration_status;
      return id == null ? "" : String(id);
    }

    if (colId === "is_duplicate") {
      if (data.is_duplicate == null) return "";
      return data.is_duplicate ? "true" : "false";
    }

    return this._normalizeValue(colId, data[colId]);
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
    if (value == null || value === "") {
      if (
        colId === "contentdm_collection_id" ||
        colId === "aspace_collection_id"
      ) {
        return "—";
      }
      return "";
    }

    const opts = this._optionsForColumn(colId);
    if (!opts || !opts.length) return String(value);

    const found = opts.find(o => String(o.value) === String(value));
    return found ? found.label : String(value);
  }

  // Builds a label-based sort key for select-like columns.
  _labelSortKey(colId, node) {
    const explicit = node?.data?.[`${colId}_sort`];
    if (explicit) return explicit;

    const labelField = node?.data?.[`${colId}_label`];
    const label = labelField || this._optionLabelFor(colId, node?.data?.[colId] ?? "") || "";
    return label.trim().toLowerCase();
  }

  // Applies notes-match highlighting without replacing the editable notes input.
  _syncNotesHighlight(elem, node, value) {
    const notes = String(value ?? "");
    const query = String(this.currentQuery || "").trim();
    const input = elem.querySelector("input[name='notes']");

    elem.classList.remove("wb-custom-match");
    input?.classList.remove("wb-custom-match");

    if (!input || !notes || !query) {
      return;
    }

    const predicate = this.currentFilterPredicate;
    if (typeof predicate === "function" && !predicate(node)) {
      return;
    }

    const title = String(node?.title || "").toLowerCase();
    const normalizedQuery = query.toLowerCase();
    const noteMatches = normalizedQuery && notes.toLowerCase().includes(normalizedQuery);
    const titleMatches = normalizedQuery && title.includes(normalizedQuery);

    if (noteMatches && !titleMatches) {
      input.classList.add("wb-custom-match");
    }
  }

  // Applies title highlighting only when the visible node title itself matches the query.
  _syncTitleHighlight(titleElem, node) {
    titleElem.classList.remove("wb-title-match");

    const query = String(this.currentQuery || "").trim().toLowerCase();
    if (!query) return;

    const title = String(node?.title || "").toLowerCase();
    if (!title.includes(query)) return;

    titleElem.classList.add("wb-title-match");
  }

  // Renders and positions the column filter dropdown.
  _showDropdownFilter(anchorEl, colId, colIdx, opts = {}) {
    const isInline = typeof opts.onSelect === "function";
    const currentValue = opts.currentValue;

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
    } else if (colId === "is_duplicate") {
      options = [
        { value: "true", label: "True" },
        { value: "false", label: "False" }
      ];
    } else if (colId === "contentdm_collection_id") {
      options = this.contentdmCollectionOptions || [];
    } else if (colId === "aspace_collection_id") {
      options = this.aspaceCollectionOptions || [];
    } else if (colId === "file_type") {
      options = this.fileTypeOptions || [];
    } else if (colId === "aspace_linking_status") {
      options = [
        { value: "true", label: "True" },
        { value: "false", label: "False" }
      ];
    } else {
      const values = this.columnValueCache.get(colId) || new Set();
      options = [...values].sort().map(v => ({ value: v, label: v }));
    }

    const allowInlineClear =
      isInline &&
      (colId === "contentdm_collection_id" || colId === "aspace_collection_id");

    options = options.sort((a, b) => a.label.localeCompare(b.label, undefined, { sensitivity: "base" }));
    if (allowInlineClear) {
      options.unshift({ value: "", label: "None" });
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
      select.size = Math.max(1, Math.min(select.options.length, 8));
    } else {
      select.size = Math.max(Math.min(select.options.length, 8), 4);
    }

    if (isInline) {
      if (currentValue != null) {
        select.value = String(currentValue);
      } else {
        select.value = "";
      }
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
      document.dispatchEvent(new CustomEvent("wunderbaum:filtersChanged"));
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

  // Opens the shared dropdown popup to edit a cell value inline instead of applying a column filter
  _showInlineEditor(cell, node, colId) {
    this._showDropdownFilter(cell, colId, null, {
      currentValue: this._normalizeValue(
        colId,
        colId === "assigned_to" ? node.data.assigned_to_id : node.data[colId]
      ),
      onSelect: (value) => {
        const normalized = this._normalizeValue(colId, value);

        if (colId === "assigned_to") {
          node.data.assigned_to_id = normalized === "unassigned" ? null : normalized;
          node.data.assigned_to = this._optionLabelFor("assigned_to", normalized);
        } else {
          node.data[colId] = normalized;
        }

        this._saveCellChange(node, colId, normalized);

        const label = colId === "assigned_to"
          ? node.data.assigned_to
          : this._optionLabelFor(colId, normalized);
        cell.textContent = label || "Unassigned";
        cell.classList.add("wb-select-like");
      }
    });
  }

  // Displays the dropdown popup anchored to a cell and commits the selected value back to the node
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

  // Cancels an active search
  _cancelActiveSearch() {
    this._filterSeq += 1;
    this._cancelInflight();
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
    if (this._loadingCount == null) this._loadingCount = 0;

    let container = document.querySelector(".wb-loading-container");
    const toolbar = input.closest(".wb-toolbar") || input.parentElement;
    if (!container) {
      container = document.createElement("div");
      container.className = "wb-loading-container";
      container.style.display = "none";
      container.style.position = "absolute";
      container.style.left = "0";
      container.style.pointerEvents = "none";
      (toolbar || document.body).appendChild(container);
    }

    if (toolbar && getComputedStyle(toolbar).position === "static") {
      toolbar.style.position = "relative";
    }

    let statusEl = container.querySelector(".wb-loading");
    if (!statusEl) {
      statusEl = document.createElement("div");
      statusEl.className = "wb-loading";
      container.appendChild(statusEl);
    }

    if (isLoading) {
      this._loadingCount += 1;
      statusEl.textContent = text;
      if (toolbar) {
        const topOffset = (toolbar.offsetHeight || 0) + 8;
        container.style.top = `${topOffset}px`;
      }
      container.style.display = "block";
    } else {
      this._loadingCount = Math.max(0, this._loadingCount - 1);
      if (this._loadingCount === 0) {
        statusEl.textContent = "";
        container.style.display = "none";
        const bar = container.querySelector(".wb-progress");
        if (bar) bar.remove();
      }
    }
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

      if (field === "assigned_to" || data.field === "assigned_to_id") {
        node.data.assigned_to_id = data.value;
        node.data.assigned_to = data.label || "Unassigned";
      } else {
        node.data[field] = data.value ?? value;
      }
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

  // Displays count for query search matches
  _updateMatchCount(count, notesMatchCount = 0) {
    const input = document.getElementById("tree-filter");
    if (!input) return;

    const normalizedCount = Number(count);
    const resolvedCount = Number.isFinite(normalizedCount) ? normalizedCount : 0;
    this.currentMatchCount = resolvedCount;
    this.currentNotesMatchCount = Number.isFinite(Number(notesMatchCount)) ? Number(notesMatchCount) : 0;

    let el = document.getElementById("tree-match-count");
    const toolbar = input.closest(".wb-toolbar") || input.parentElement;

    if (!el) {
      el = document.createElement("div");
      el.id = "tree-match-count";
      el.className = "wb-match-count wb-loading-style";
      el.style.position = "absolute";
      el.style.pointerEvents = "none";
      el.style.zIndex = "10";

      (toolbar || document.body).appendChild(el);
    }

    if (toolbar && getComputedStyle(toolbar).position === "static") {
      toolbar.style.position = "relative";
    }

    const topOffset = (toolbar?.offsetHeight || 0) + 8;
    el.style.top = `${topOffset}px`;
    el.style.left = "0";
    el.style.display = "block";
    let text = `${resolvedCount.toLocaleString()} matches`;
    if (this.currentNotesMatchCount > 0) {
      text += ` (${this.currentNotesMatchCount.toLocaleString()} notes matches)`;
    }

    el.textContent = text;
  }

  _showMatchCountStatus(text) {
    const input = document.getElementById("tree-filter");
    if (!input) return;

    let el = document.getElementById("tree-match-count");
    const toolbar = input.closest(".wb-toolbar") || input.parentElement;

    if (!el) {
      el = document.createElement("div");
      el.id = "tree-match-count";
      el.className = "wb-match-count wb-loading-style";
      el.style.position = "absolute";
      el.style.pointerEvents = "none";
      el.style.zIndex = "10";

      (toolbar || document.body).appendChild(el);
    }

    if (toolbar && getComputedStyle(toolbar).position === "static") {
      toolbar.style.position = "relative";
    }

    const topOffset = (toolbar?.offsetHeight || 0) + 8;
    el.style.top = `${topOffset}px`;
    el.style.left = "0";
    el.style.display = "block";
    el.textContent = text;
  }

  // Updates or creates the selection progress bar based on processed vs total nodes.
  _updateProgress(processed, total, label = "Selecting…") {
    const container = document.querySelector(".wb-loading-container");
    if (!container) return;

    let bar = container.querySelector(".wb-progress");
    if (!bar) {
      bar = document.createElement("div");
      bar.className = "wb-progress";
      bar.innerHTML = `
        <div class="wb-progress-label"></div>
        <div class="wb-progress-track">
          <div class="wb-progress-fill"></div>
        </div>
      `;
      container.appendChild(bar);
    }

    const percent = total > 0 ? Math.round((processed / total) * 100) : 0;

    bar.querySelector(".wb-progress-label").textContent =
      `${label} ${percent}%`;

    bar.querySelector(".wb-progress-fill").style.width = `${percent}%`;
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

  // Builds the number of selected assets that match each folder
  _buildFolderMatchCounts(assets) {
    const counts = new Map();

    for (const asset of assets) {
      const parentId =
        asset.parent_folder_id ??
        asset.folder_id;

      const folderIds = new Set(
        [
          ...(Array.isArray(asset.path) ? asset.path : []),
          parentId
        ]
          .filter((id) => id != null)
          .map(String)
      );

      for (const folderId of folderIds) {
        counts.set(
          folderId,
          (counts.get(folderId) || 0) + 1
        );
      }
    }

    this.folderMatchCounts = counts;
  }
}
