// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, volumeId: Number };

  // State
  columnFilters = new Map();
  assetsLoadedFor = new Set();         // folderId -> loaded once?
  currentFilterPredicate = null;
  currentFilterOpts = null;
  currentQuery = "";

  _filterTimer = null;
  _filterSeq = 0;

  // Track folders we expanded due to the active filter (so we can collapse on clear)
  expandedByFilter = new Set();

  async connect() {
    try {
      const res = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin",
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

        // If your nodes don't include `key`, uncomment the next line:
        // keyMap: { key: "id", title: "title" },

        filter: {
          autoApply: true,
          autoExpand: false,     // we expand selectively after filtering
          matchBranch: true,
          fuzzy: false,
          hideExpanders: false,
          highlight: false,
          leavesOnly: false,
          mode: "dim",           // "hide" is faster; keep "dim" if you prefer the look
          noData: true,
          menu: true,
        },

        // ---- Columns (unchanged from your snippet) ----
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
              </select>`,
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
              </select>`,
          },
          { id: "file_size", classes: "wb-helper-center", title: "File size", width: "150px" },
          {
            id: "notes",
            classes: "wb-helper-center",
            title: "Notes",
            width: "500px",
            html: `<input type="text" tabindex="-1">`,
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
              </select>`,
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
              </select>`,
          },
          {
            id: "preservica_reference_id",
            classes: "wb-helper-center",
            title: "Preservica Reference",
            width: "150px",
            html: `<input type="text" tabindex="-1">`,
          },
          {
            id: "aspace_linking_status",
            classes: "wb-helper-center",
            filterable: true,
            title: "ASpace linking status",
            width: "150px",
            html: `<input type="checkbox" tabindex="-1">`,
          },
          { id: "isilon_date", classes: "wb-helper-center", title: "Isilon date created", width: "150px" },
        ],

        icon: ({ node }) => {
          if (!node.data.folder) return "bi bi-files";
        },

        // ---- FAST: folders lazy-load via URL ----
        lazyLoad: (e) => {
          if (!e.node?.data?.folder) return [];
          const id = e.node.data.id; // folder id expected by server
          return {
            url: `/volumes/${this.volumeIdValue}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(id)}`,
            options: { headers: { Accept: "application/json" }, credentials: "same-origin" },
          };
        },

        // ---- Assets load when a folder is expanded (once) ----
        expand: async (e) => {
          const node = e.node;
          if (!node?.data?.folder) return;

          await this._ensureAssetsForFolder(String(node.key ?? node.data.id));

          // If a filter is active, re-run so new rows participate, and keep matches visible
          this._reapplyFilterIfAny();
        },

        // Class API signature
        postProcess: (e) => {
          e.result = e.response;
        },

        // ---- Your render logic ----
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

        // Initial root
        source,
      });

      this._setupInlineFilter();
    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
  }

  // ---------------- Deep, complete filtering ----------------

  _setupInlineFilter() {
    const input = document.getElementById("tree-filter");
    if (!input) return;

    input.addEventListener("input", () => {
      clearTimeout(this._filterTimer);
      this._filterTimer = setTimeout(() => this._runDeepFilter(input.value || ""), 300);
    });
  }

  async _runDeepFilter(raw) {
    const mySeq = ++this._filterSeq;
    const q = (raw || "").trim().toLowerCase();
    this.currentQuery = q;

    // Clear: reset filter & collapse what we expanded due to filter
    if (!q && this.columnFilters.size === 0) {
      this.currentFilterPredicate = null;
      this.currentFilterOpts = null;
      this.tree.clearFilter();
      this._collapseFilterExpansions();
      return;
    }

    // 1) Server search to get ALL matches (folders + assets)
    const [folders, assets] = await Promise.all([
      fetch(`/volumes/${this.volumeIdValue}/file_tree_folders_search?q=${encodeURIComponent(q)}`,
            { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(r => r.ok ? r.json() : []),
      fetch(`/volumes/${this.volumeIdValue}/file_tree_assets_search?q=${encodeURIComponent(q)}`,
            { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then(r => r.ok ? r.json() : []),
    ]);
    if (mySeq !== this._filterSeq) return;

    // 2) Build the set S of folders to hydrate
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
    const parentIds = Array.from(S);

    // 3) Hydrate children for S in batches (folders + assets)
    await this._hydrateChildrenForParents(parentIds, mySeq);

    // 4) Apply predicate to everything now in memory
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

    // 5) Expand EACH match chain root->…->parent, awaiting lazy loads.
    await this._expandAllMatchChains(folders, assets);

    // Optional: open a few matched folders to reveal their immediate children
    this._autoExpandSomeMatchingFolders(20);
  }

  // ---------------- Helpers: hydration & expansion ----------------

  async _hydrateChildrenForParents(parentIds, mySeq, batchSize = 25) {
    if (!parentIds.length) return;
    const base = `/volumes/${this.volumeIdValue}`;

    for (let i = 0; i < parentIds.length; i += batchSize) {
      if (mySeq !== this._filterSeq) return;
      const ids = parentIds.slice(i, i + batchSize);
      const qs = ids.map(id => `parent_ids[]=${encodeURIComponent(id)}`).join("&");

      // If your backend DOES NOT support parent_ids[], uncomment per-id fallback below
      const [childFolders, childAssets] = await Promise.all([
        fetch(`${base}/file_tree_folders.json?${qs}`, { headers: { Accept: "application/json" }, credentials: "same-origin" })
          .then(r => r.ok ? r.json() : []),
        fetch(`${base}/file_tree_assets.json?${qs}`,  { headers: { Accept: "application/json" }, credentials: "same-origin" })
          .then(r => r.ok ? r.json() : []),
      ]);

      // Fallback per-id (slower):
      // const childFolders = (await Promise.all(ids.map(id =>
      //   fetch(`${base}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(id)}`, { headers: {Accept:"application/json"}, credentials:"same-origin" })
      //     .then(r => r.ok ? r.json() : [])))).flat();
      // const childAssets = (await Promise.all(ids.map(id =>
      //   fetch(`${base}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(id)}`, { headers: {Accept:"application/json"}, credentials:"same-origin" })
      //     .then(r => r.ok ? r.json() : [])))).flat();

      const byParent = new Map(); // pid -> nodes
      for (const n of [...childFolders, ...childAssets]) {
        const pid = String(n.parent_folder_id ?? n.parent_id ?? "");
        if (!pid) continue;
        if (!byParent.has(pid)) byParent.set(pid, []);
        byParent.get(pid).push(n);
      }

      // Attach to any matching parent already present in the tree
      for (const pid of ids) {
        const parentNode = this._findNodeByKeyOrId(pid);
        if (!parentNode) continue;

        const existing = new Set((parentNode.children || []).map(ch => String(ch.key ?? ch.data?.id)));
        const kids = byParent.get(pid) || [];
        const toAdd = kids.filter(k => !existing.has(String(k.key ?? k.id)));
        if (toAdd.length) parentNode.addChildren?.(toAdd);
      }

      // Yield to UI
      await new Promise(r => requestAnimationFrame(r));
    }
  }

  // Find node robustly by 'key' or fallback to data.id
  _findNodeByKeyOrId(id) {
    const key = String(id);
    let n = this.tree.getNodeByKey?.(key);
    if (n) return n;
    this.tree.visit((node) => {
      if (String(node.key ?? node.data?.id) === key) { n = node; return false; }
    });
    return n;
  }

  async _expandPath(pathIds) {
    for (const id of pathIds.map(String)) {
      const node = this._findNodeByKeyOrId(id);
      if (!node) return; // Parent not attached (should be after hydration)
      if (node.lazy && !node.children) {
        try { await node.loadLazy(); } catch (_) {}
      }
      if (!node.expanded) {
        node.setExpanded?.(true);
        this.expandedByFilter.add(String(node.key ?? node.data.id));
      }
      // Ensure assets for this folder so leaf matches can show
      await this._ensureAssetsForFolder(String(node.key ?? node.data.id));
      await new Promise(r => requestAnimationFrame(r));
    }
  }

  async _expandAllMatchChains(folderHits, assetHits, chunkSize = 15) {
    const chains = [];

    // Folders: ancestors + this folder
    for (const f of folderHits) {
      const path = Array.isArray(f.path) ? f.path.map(String) : [];
      chains.push([...path, String(f.id)]);
    }
    // Assets: ancestors + parent folder
    for (const a of assetHits) {
      const path = Array.isArray(a.path) ? a.path.map(String) : [];
      const pid = a.parent_folder_id ?? a.folder_id ?? a.parent_id;
      if (pid != null) chains.push([...path, String(pid)]);
    }

    // Dedup
    const seen = new Set();
    const uniq = [];
    for (const c of chains) {
      const k = c.join(">");
      if (!seen.has(k)) { seen.add(k); uniq.push(c); }
    }

    // Expand in small batches; reapply predicate as we go
    for (let i = 0; i < uniq.length; i += chunkSize) {
      const batch = uniq.slice(i, i + chunkSize);
      await Promise.all(batch.map(c => this._expandPath(c)));
      this._reapplyFilterIfAny();
      await new Promise(r => requestAnimationFrame(r));
    }
  }

  async _ensureAssetsForFolder(folderId) {
    const id = String(folderId);
    if (this.assetsLoadedFor.has(id)) return;

    const node = this._findNodeByKeyOrId(id);
    if (!node || node.data?.folder !== true) { this.assetsLoadedFor.add(id); return; }

    const url = `/volumes/${this.volumeIdValue}/file_tree_assets.json?parent_folder_id=${encodeURIComponent(id)}`;
    const r = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" });
    if (!r.ok) { this.assetsLoadedFor.add(id); return; }

    const assets = await r.json();
    if (Array.isArray(assets) && assets.length) {
      const existing = new Set((node.children || []).map(ch => String(ch.key ?? ch.data?.id)));
      const toAdd = assets.filter(a => !existing.has(String(a.key ?? a.id)));
      if (toAdd.length) node.addChildren?.(toAdd);
    }

    this.assetsLoadedFor.add(id);
  }

  _reapplyFilterIfAny() {
    if (this.currentFilterPredicate) {
      this.tree.filterNodes(this.currentFilterPredicate, this.currentFilterOpts || {});
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
        this.expandedByFilter.add(String(node.key ?? node.data.id));
        expanded += 1;
      }
    });
  }

  _collapseFilterExpansions() {
    // Collapse only what we expanded due to filter (leave user-expansions alone)
    for (const key of this.expandedByFilter) {
      const node = this._findNodeByKeyOrId(key);
      if (node && node.expanded) node.setExpanded(false);
    }
    this.expandedByFilter.clear();
  }

  // ---------------- Column popup filter (unchanged from your code) ----------------

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
      // re-run deep filter with the same query text
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

  disconnect() {
    clearTimeout(this._filterTimer);
  }
}
