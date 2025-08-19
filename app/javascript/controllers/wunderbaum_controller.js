
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
          matchBranch: true,
          fuzzy: false,
          hideExpanders: false,
          highlight: false,
          leavesOnly: false,
          mode: "dim",
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
            html: `
              <select tabindex="-1">
                <option value="pending" selected>Pending</option>
              </select>`
          },
          {
            id: "assigned_to",
            classes: "wb-helper-center",
            filterable: true,
            title: "Assigned To",
            width: "150px",
            html: `
              <select tabindex="-1">
                <option value="unassigned" selected>Unassigned</option>
              </select>`
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
            width: "150px",
            html: `<input type="text" tabindex="-1">`
          },
          { id: "file_size",
            classes: "wb-helper-center",
            title: "File size",
            width: "150px"
          },
          { id: "isilon_date",
            classes: "wb-helper-center",
            title: "Isilon date created",
            width: "150px"
          },
          {
            id: "contentdm_collection",
            classes: "wb-helper-center",
            filterable: true,
            title: "Contentdm Collection",
            width: "150px",
            html: `
              <select tabindex="-1">
                <option value="" selected></option>
              </select>`
          },
          {
            id: "aspace_collection",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace Collection",
            width: "150px",
            html: `
              <select tabindex="-1">
                <option value="" selected></option>
              </select>`
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
          await this._ensureAssetsForFolderCancellable(String(node.key ?? node.data?.key ?? node.data?.id), this._filterSeq);
          this._reapplyFilterIfAny();
        },

        postProcess: (e) => { e.result = e.response; },

        render: (e) => {
          const isFolder = e.node.data.folder === true;

          for (const colInfo of Object.values(e.renderColInfosById)) {
            colInfo.elem.dataset.colId = colInfo.id;
            const colId = colInfo.id;
            const rawValue = e.node.data[colId];
            const value = isFolder || rawValue == null ? "" : String(rawValue);

            const hasInteractive = colInfo.elem.querySelector("input, select, textarea");
            if (!hasInteractive) colInfo.elem.innerHTML = value;

            const select = colInfo.elem.querySelector("select");
            if (select) select.value = select.querySelector("option[selected]")?.value ?? "";
          }

          const titleElem = e.nodeElem.querySelector("span.wb-title");
          const title = e.node.title || "";
          if (titleElem) {
            titleElem.innerHTML = isFolder
              ? title
              : `<a href="${e.node.data.url}" class="asset-link" data-turbo="false">${title}</a>`;
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
            this.showDropdownFilter(icon, colId);
          }
        },

        change: (e) => {
          const util = e.util;
          const colId = e.info.colId;
          e.node.data[colId] = util.getValueFromElem(e.inputElem, true);
        },

        source
      });

      this._setupInlineFilter();
    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
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

  async _runDeepFilter(raw) {
    this._cancelInflight();
    const mySeq = ++this._filterSeq;

    const q = (raw || "").trim().toLowerCase();
    this.currentQuery = q;

    if (!q && this.columnFilters.size === 0) {
      this.currentFilterPredicate = null;
      this.currentFilterOpts = null;
      this.tree.clearFilter();
      this._collapseFilterExpansions();
      this._setLoading(false);
      return;
    }

    this._setLoading(true, "Searching…");

    const searchCtrl = this._beginFetchGroup();
    let folders = [], assets = [];
    try {
      [folders, assets] = await Promise.all([
        this._fetchJson(`/volumes/${this.volumeIdValue}/file_tree_folders_search.json?q=${encodeURIComponent(q)}`, searchCtrl).catch(() => []),
        this._fetchJson(`/volumes/${this.volumeIdValue}/file_tree_assets_search.json?q=${encodeURIComponent(q)}`,  searchCtrl).catch(() => []),
      ]);
    } finally {
      this.inflightControllers.delete(searchCtrl);
    }
    if (mySeq !== this._filterSeq) return;

    const S = new Set();
    for (const r of [...folders, ...assets]) {
      const path = Array.isArray(r.path) ? r.path : [];
      for (const id of path) S.add(String(id));
    }
    for (const f of folders) S.add(String(f.id));
    for (const a of assets) {
      const pid = a.parent_folder_id ?? a.folder_id ?? a.parent_id;
      if (pid != null) S.add(String(pid));
    }

    const parentKeys = Array.from(S);
    const BATCH = 20;
    const totalBatches = Math.max(1, Math.ceil(parentKeys.length / BATCH));

    for (let i = 0; i < parentKeys.length; i += BATCH) {
      if (mySeq !== this._filterSeq) return;

      const idx = Math.floor(i / BATCH) + 1;
      this._setLoading(true, `Loading results… (${idx}/${totalBatches})`);

      const ids = parentKeys.slice(i, i + BATCH);
      const ctrl = this._beginFetchGroup();
      try {
        const results = await Promise.all(ids.map(async (pid) => {
          const base = `/volumes/${this.volumeIdValue}`;
          const [childFolders, childAssets] = await Promise.all([
            this._fetchJson(`${base}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(pid)}`, ctrl).catch(() => []),
            this._fetchJson(`${base}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(pid)}`,  ctrl).catch(() => []),
          ]);
          return { pid, childFolders, childAssets };
        }));

        if (mySeq !== this._filterSeq) return;

        for (const { pid, childFolders, childAssets } of results) {
          const parentNode = this._findNodeByKey(pid);
          if (!parentNode) continue;

          const existing = new Set((parentNode.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
          const toAdd = [...(childFolders || []), ...(childAssets || [])]
            .filter(n => !existing.has(String(n.key ?? n.id)));
          if (toAdd.length) parentNode.addChildren?.(toAdd);
        }
      } finally {
        this.inflightControllers.delete(ctrl);
      }

      this._applyPredicate(q);
      await new Promise(r => requestAnimationFrame(r));
    }

    if (mySeq !== this._filterSeq) return;

    this._applyPredicate(q);

    await this._expandAllMatchChainsCancellable(folders, assets, mySeq, 10);

    this._autoExpandSomeMatchingFolders(20);

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
    const opts = { leavesOnly: false, matchBranch: true, mode: "dim" };
    this.currentFilterPredicate = predicate;
    this.currentFilterOpts = opts;
    this.tree.filterNodes(predicate, opts);
  }

  _reapplyFilterIfAny() {
    if (this.currentFilterPredicate) {
      this.tree.filterNodes(this.currentFilterPredicate, this.currentFilterOpts || {});
    }
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

  async _hydrateSingleParentByKey(parentKey, mySeq) {
    if (mySeq !== this._filterSeq) return;
    const pid = String(parentKey);
    const base = `/volumes/${this.volumeIdValue}`;

    const ctrl = this._beginFetchGroup();
    try {
      const [childFolders, childAssets] = await Promise.all([
        this._fetchJson(`${base}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(pid)}`, ctrl).catch(() => []),
        this._fetchJson(`${base}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(pid)}`,  ctrl).catch(() => []),
      ]);
      if (mySeq !== this._filterSeq) return;

      const parentNode = this._findNodeByKey(pid);
      if (!parentNode) return;

      const existing = new Set((parentNode.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
      const toAdd = [...(childFolders || []), ...(childAssets || [])]
        .filter(n => !existing.has(String(n.key ?? n.id)));
      if (toAdd.length) parentNode.addChildren?.(toAdd);
    } finally {
      this.inflightControllers.delete(ctrl);
    }
  }

  async _ensureAssetsForFolderCancellable(folderKey, mySeq) {
    const k = String(folderKey);
    if (this.assetsLoadedFor.has(k)) return;

    const node = this._findNodeByKey(k);
    if (!node || node.data?.folder !== true) { this.assetsLoadedFor.add(k); return; }

    const ctrl = this._beginFetchGroup();
    try {
      const url = `/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(k)}`;
      const assets = await this._fetchJson(url, ctrl);
      if (mySeq !== this._filterSeq) return;

      if (Array.isArray(assets) && assets.length) {
        const existing = new Set((node.children || []).map(ch => String(ch.key ?? ch.data?.key ?? ch.data?.id)));
        const toAdd = assets.filter(a => !existing.has(String(a.key ?? a.id)));
        if (toAdd.length) node.addChildren?.(toAdd);
      }
    } catch {
      // ignore
    } finally {
      this.inflightControllers.delete(ctrl);
      this.assetsLoadedFor.add(k);
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

  _autoExpandSomeMatchingFolders(cap = 20) {
    if (!this.currentFilterPredicate || !this.tree) return;
    let expanded = 0;
    this.tree.visit((node) => {
      if (expanded >= cap) return false;
      const isFolder = node.data?.folder === true;
      if (!isFolder) return;
      let matched = false;
      try { matched = this.currentFilterPredicate(node); } catch (_) {}
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

  showDropdownFilter(anchorEl, colId) {
    const popupSelector = `[data-popup-for='${colId}']`;
    const existing = document.querySelector(popupSelector);
    if (existing) { existing.remove(); return; }

    const popup = document.createElement("div");
    popup.classList.add("wb-popup");
    popup.setAttribute("data-popup-for", colId);

    const select = document.createElement("select");
    select.classList.add("popup-select");

    const colDef = this.tree.columns.find((c) => c.id === colId);

    if (colId === "aspace_linking_status") {
      select.innerHTML = `
        <option value="true">True</option>
        <option value="false">False</option>
        <option value="">⨉ Clear Filter</option>
      `;
    } else if (colDef?.html?.includes("<select")) {
      const tmp = document.createElement("div");
      tmp.innerHTML = colDef.html;
      const original = tmp.querySelector("select");
      if (original) {
        for (const opt of original.options) select.appendChild(opt.cloneNode(true));
        if (!Array.from(select.options).some((o) => o.value === "")) {
          select.appendChild(new Option("⨉ Clear Filter", ""));
        }
      }
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

    select.addEventListener("change", (e) => {
      const selectedValue = e.target.value;
      if (selectedValue === "") this.columnFilters.delete(colId);
      else this.columnFilters.set(colId, selectedValue);
      this._runDeepFilter(this.currentQuery);
    });

    popup.appendChild(select);
    document.body.appendChild(popup);

    const updatePos = () => {
      const r = anchorEl.getBoundingClientRect();
      popup.style.position = "absolute";
      popup.style.left = `${window.scrollX + r.left}px`;
      popup.style.top = `${window.scrollY + r.top - popup.offsetHeight - 4}px`;
      popup.style.zIndex = "1000";
    };
    requestAnimationFrame(updatePos);

    const reposition = () => requestAnimationFrame(updatePos);
    window.addEventListener("scroll", reposition, true);
    window.addEventListener("resize", reposition);

    const obs = new MutationObserver(() => {
      if (!document.body.contains(popup)) {
        window.removeEventListener("scroll", reposition, true);
        window.removeEventListener("resize", reposition);
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
    const filterBtnIcon = document.querySelector(".icon-button .search-icon");

    if (!isLoading) {
      document.querySelector(".wb-loading")?.remove();
      return;
    }

    if (!filterBtnIcon) {
      console.warn("Filter button icon not found, cannot place loading indicator");
      return;
    }

    let el = document.querySelector(".wb-loading");
    if (!el) {
      el = document.createElement("div");
      el.className = "wb-loading";
      filterBtnIcon.closest("button")?.insertAdjacentElement("afterend", el);
    }
    el.textContent = text;
  }

}
