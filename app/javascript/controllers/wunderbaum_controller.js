import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, 
                    volumeId: Number };
  columnFilters = new Map();
  childrenPromiseCache = new Map();
  childrenCache = new Map();
  MAX_MATCHES = 200;

  disconnect() {
    document.removeEventListener("click", this.handleFilterCommandClick);
  }

  async connect() {
    document.addEventListener("click", this.handleFilterCommandClick);

    try {
      const res = await fetch(this.urlValue);
      const data = await res.json();
      console.log("Wunderbaum connect, url:", this.urlValue);

      this.tree = new Wunderbaum({
        element: this.element,
        autoActivate: true,
        checkbox: true,
        columnsResizable: true, 
        fixedCol: true,
        id: "tree",
        keyboard: true,
        lazy: true,
        selectMode: "hier",
        source: data,
        columns: [
          { id: "*",
            title: "Filename",
            width: "500px"
          },
          {
            id:      "migration_status",
            classes: "wb-helper-center",
            filterable: true,
            title:   "Migration status",
            width:   "150px",    
            html: `
              <select tabindex="-1">
                <option value="pending" selected>Pending</option>
              </select>`
          },
          {
            id:      "assigned_to",
            classes: "wb-helper-center",
            filterable: true,
            title:   "Assigned To",
            width:   "150px",
            html: `
              <select tabindex="-1">
                <option value="unassigned" selected>Unassigned</option>
              </select>`
          },
          { id: "file_size",
            classes: "wb-helper-center",
            title: "File size",
            width: "150px"
          },
          { id: "notes",
            classes: "wb-helper-center",
            title: "Notes",
            width: "500px",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id:      "contentdm_collection",
            classes: "wb-helper-center",
            filterable: true,
            title:   "Contentdm Collection",
            width:   "150px",
            html: `
              <select tabindex="-1">
                <option value="" selected></option>
              </select>`
          },
          {
            id:      "aspace_collection",
            classes: "wb-helper-center",
            filterable: true,
            title:   "ASpace Collection",
            width:   "150px",
            html: `
              <select tabindex="-1">
                <option value="" selected></option>
              </select>`
          },
          { id: "preservica_reference_id",
            classes: "wb-helper-center",
            title: "Preservica Reference",
            width: "150px",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id:      "aspace_linking_status",
            classes: "wb-helper-center",
            filterable: true,
            title:   "ASpace linking status",
            width:   "150px",
            html:    `<input type="checkbox" tabindex="-1">`
          },
          { id: "isilon_date",
            classes: "wb-helper-center",
            title: "Isilon date created",
            width: "150px"
          },
        ],

        filter: {
          autoApply: true,
          autoExpand: true,
          matchBranch: true,
          fuzzy: false,
          hideExpanders: false,
          highlight: false,
          leavesOnly: false,
          mode: "dim",
          noData: true,
          menu: true
        },
        
        icon: ({ node }) => {
          if (!node.data.folder) {
            return "bi bi-files";
          }
        },

  lazyLoad: (e) => {
  const node = e.node;
  if (!node?.data?.folder) return [];

  const parentId = String(node.key ?? node.data.id);

  // Reuse in-flight promise
  let p = this.childrenPromiseCache.get(parentId);
  if (!p) {
    const base = `/volumes/${this.volumeIdValue}`;
    const fetchJson = (url) =>
      fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" })
        .then((r) => { if (!r.ok) throw new Error(`HTTP ${r.status} ${url}`); return r.json(); });

    p = Promise.all([
      fetchJson(`${base}/file_tree_folders?parent_folder_id=${encodeURIComponent(parentId)}`),
      fetchJson(`${base}/file_tree_assets?parent_folder_id=${encodeURIComponent(parentId)}`)
    ]).then(([folders, assets]) => {
      const out = (folders || []).concat(assets || []);
      this.childrenCache.set(parentId, out);
      this.childrenPromiseCache.delete(parentId);
      return out;
    }).catch((err) => {
      console.warn("lazyLoad failed:", err);
      this.childrenPromiseCache.delete(parentId);
      return [];
    });

    this.childrenPromiseCache.set(parentId, p);
  }
  return p;
},






        // init: (e) => {
        //   const root = e.tree?.rootNode;
        //   const children = root?.children;
        //   if (!Array.isArray(children)) return;
        //   for (const folderNode of children) {
        //     if (folderNode.data?.folder) {
        //       folderNode.load();
        //     }
        //   }
        // },

        render: (e) => {
          const isFolder = e.node.data.folder === true;

          for (const colInfo of Object.values(e.renderColInfosById)) {
            colInfo.elem.dataset.colId = colInfo.id;
            const colId = colInfo.id;
            const rawValue = e.node.data[colId];
            const value = isFolder || rawValue == null ? "" : String(rawValue);

            const hasInteractive = colInfo.elem.querySelector("input, select, textarea");
            if (!hasInteractive) {
              colInfo.elem.innerHTML = value;
            }

            const select = colInfo.elem.querySelector("select");
            if (select) {
              select.value = select.querySelector("option[selected]")?.value ?? "";
            }
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
            if (!colCell) {
              return;
            }

            const icon = colCell.querySelector("[data-command='filter']");
            if (!icon) {
              return;
            }

            this.showDropdownFilter(icon, colId);
          }
        },

        change(e) {
          const util = e.util;
          const colId = e.info.colId;
          e.node.data[colId] = util.getValueFromElem(e.inputElem, true);
        },
      });

      this.setupInlineFilter();

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
  }

  setupInlineFilter() {
  var input = document.getElementById("tree-filter");
  if (!input) return;

  var debounceTimer = null;
  var inflight = null;   // AbortController for background fetch
  var seq = 0;           // stale-response guard

  function reapply(self) {
    if (typeof self.applyAllColumnFilters === "function") {
      self.applyAllColumnFilters();
    } else if (self.tree && typeof self.tree.reapplyFilter === "function") {
      self.tree.reapplyFilter();
    }
  }

  // Find a node by key (string-safe)
  function findNodeByKey(self, id) {
    var key = String(id);
    var n = self.tree && typeof self.tree.getNodeByKey === "function" ? self.tree.getNodeByKey(key) : null;
    if (n) return n;
    if (self.tree && typeof self.tree.visit === "function") {
      self.tree.visit(function(node) {
        if (String(node.key) === key) { n = node; return false; }
      });
    }
    return n;
  }

  // Load a folder node's children via lazy (folders only)
  async function ensureFolderChildrenLoaded(self, folderNode) {
    if (!folderNode) return;
    if (folderNode.lazy && !folderNode.children) {
      await folderNode.loadLazy();
    }
  }

  // Ensure a single chain of folder IDs is loaded in order (root -> ... -> targetFolder)
  async function ensureChainLoaded(self, ids, mySeq) {
    for (var i = 0; i < ids.length; i++) {
      if (mySeq !== seq) return; // stale
      var id = ids[i];
      var node = findNodeByKey(self, id);
      if (!node) return; // parent not present; stop this chain
      await ensureFolderChildrenLoaded(self, node);
      // Let DOM update and reapply current predicate so new rows participate
      reapply(self);
      await new Promise(function(resolve){ requestAnimationFrame(resolve); });
    }
  }

  // Fetch assets for a folder and add them as children if missing
  async function ensureAssetsPresent(self, parentFolderId) {
    var parentNode = findNodeByKey(self, parentFolderId);
    if (!parentNode) return;

    // Make sure folder children (folders) are loaded so we don't clobber
    await ensureFolderChildrenLoaded(self, parentNode);

    // Build a quick set of existing child keys to avoid duplicates
    var existing = {};
    if (parentNode.children && parentNode.children.length) {
      for (var i = 0; i < parentNode.children.length; i++) {
        var ch = parentNode.children[i];
        existing[String(ch.key)] = true;
      }
    }

    // Fetch assets for this folder
    var url = "/volumes/" + self.volumeIdValue + "/file_tree_assets.json?parent_folder_id=" + encodeURIComponent(parentFolderId);
    var res = await fetch(url, { headers: { Accept: "application/json" }, credentials: "same-origin" });
    if (!res.ok) return;
    var assets = await res.json();
    if (!Array.isArray(assets) || assets.length === 0) return;

    // Prepare nodes for any assets that aren't already present
    var toAdd = [];
    for (var j = 0; j < assets.length; j++) {
      var a = assets[j];
      var key = String(a.id);
      if (!existing[key]) {
        toAdd.push(a); // assumes serializer already gives {id, title, folder:false, url, parent_folder_id}
        existing[key] = true;
      }
    }

    if (toAdd.length) {
      // Wunderbaum supports addChildren on a node
      if (typeof parentNode.addChildren === "function") {
        parentNode.addChildren(toAdd);
      } else if (typeof parentNode.addChild === "function") {
        for (var k = 0; k < toAdd.length; k++) parentNode.addChild(toAdd[k]);
      }
    }

    // Expand so asset rows render (needed for filtering/highlighting to see them)
    if (!parentNode.expanded && typeof parentNode.setExpanded === "function") {
      parentNode.setExpanded(true);
    }

    // Reapply predicate so these rows are considered
    reapply(self);
    await new Promise(function(resolve){ requestAnimationFrame(resolve); });
  }

  // Fetch matches from split endpoints and normalize
  async function fetchMatches(self, q, signal) {
    var foldersRes = await fetch(
      "/volumes/" + self.volumeIdValue + "/file_tree_folders_search?q=" + encodeURIComponent(q),
      { headers: { Accept: "application/json" }, credentials: "same-origin", signal: signal }
    );
    var assetsRes  = await fetch(
      "/volumes/" + self.volumeIdValue + "/file_tree_assets_search?q=" + encodeURIComponent(q),
      { headers: { Accept: "application/json" }, credentials: "same-origin", signal: signal }
    );

    var folders = foldersRes.ok ? await foldersRes.json() : [];
    var assets  = assetsRes.ok  ? await assetsRes.json()  : [];

    var folderHits = Array.isArray(folders) ? folders.map(function(f) {
      return Object.assign({}, f, { folder: true,  path: Array.isArray(f.path) ? f.path : [] });
    }) : [];

    var assetHits = Array.isArray(assets) ? assets.map(function(a) {
      return Object.assign({}, a, { folder: false, path: Array.isArray(a.path) ? a.path : [] });
    }) : [];

    return folderHits.concat(assetHits);
  }

  input.addEventListener("input", function(e) {
    var self = this; // WRONG in normal functions; fix by binding to controller
  }.bind(this)); // bind controller so `this` works inside

  // Real handler (with debounce)
  input.addEventListener("input", (e) => {
    var query = (e.target.value || "").trim().toLowerCase();
    this.currentQuery = query;

    // Immediately use the same filter path your popups use (what "worked" before)
    reapply(this);

    if (!query) {
      if (inflight && typeof inflight.abort === "function") inflight.abort();
      return;
    }

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(async () => {
      var mySeq = ++seq;

      if (inflight && typeof inflight.abort === "function") inflight.abort();
      inflight = new AbortController();

      try {
        var matches = await fetchMatches(this, query, inflight.signal);
        if (mySeq !== seq) return;

        // 1) Ensure all ancestor chains exist (folders only lazy load)
        for (var rIdx = 0; rIdx < matches.length; rIdx++) {
          var r = matches[rIdx];
          var path = Array.isArray(r.path) ? r.path : [];
          if (path.length) {
            // load each ancestor step-by-step
            var chain = [];
            for (var p = 0; p < path.length; p++) {
              var id = String(path[p]);
              chain.push(id);
            }
            await ensureChainLoaded(this, chain, mySeq);
          }
        }

        // 2) Ensure matched folders themselves are loaded (so their immediate children are there)
        for (var i = 0; i < matches.length; i++) {
          var mf = matches[i];
          if (mf && mf.folder === true) {
            var folderNode = findNodeByKey(this, mf.id);
            if (folderNode) {
              await ensureFolderChildrenLoaded(this, folderNode);
              // don't auto-expand folders here; let your predicate decide visibility
              reapply(this);
              await new Promise(function(resolve){ requestAnimationFrame(resolve); });
            }
          }
        }

        // 3) Ensure parents of matched assets have their assets present (and expand them)
        for (var j = 0; j < matches.length; j++) {
          var ma = matches[j];
          if (ma && ma.folder !== true) {
            var pid = (ma.parent_folder_id != null) ? ma.parent_folder_id :
                      (ma.folder_id != null) ? ma.folder_id :
                      (ma.parent_id != null) ? ma.parent_id : null;
            if (pid == null) continue;
            await ensureAssetsPresent(this, pid);
          }
        }

        // Final reapply so the client filter reflects everything we just added
        reapply(this);

      } catch (err) {
        // ignore AbortError; keep client-side filter behavior
      } finally {
        inflight = null;
      }
    }, 250);
  });
}



  


  showDropdownFilter(anchorEl, colId) {
    const popupSelector = `[data-popup-for='${colId}']`;
    const existing = document.querySelector(popupSelector);

    if (existing) {
      existing.remove();
      return;
    }

    const popup = document.createElement("div");
    popup.classList.add("wb-popup");
    popup.setAttribute("data-popup-for", colId);

    const select = document.createElement("select");
    select.classList.add("popup-select");

    const colDef = this.tree.columns.find(c => c.id === colId);

    if (colId === "aspace_linking_status") {
      select.innerHTML = `
        <option value="true">True</option>
        <option value="false">False</option>
        <option value="">⨉ Clear Filter</option>
      `;
    } else if (colDef?.html?.includes("<select")) {
      const tempWrapper = document.createElement("div");
      tempWrapper.innerHTML = colDef.html;
      const originalSelect = tempWrapper.querySelector("select");

      if (originalSelect) {
        for (const opt of originalSelect.options) {
          select.appendChild(opt.cloneNode(true));
        }

        const hasClear = Array.from(select.options).some(opt => opt.value === "");
        if (!hasClear) {
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
        sorted.map(v => `<option value="${v}">${v}</option>`).join("") +
        `<option value="">⨉ Clear Filter</option>`;
    }

    select.addEventListener("change", (e) => {
      const selectedValue = e.target.value;

      if (selectedValue === "") {
        this.columnFilters.delete(colId);
      } else {
        this.columnFilters.set(colId, selectedValue);
      }

      this.applyAllColumnFilters();
    });

    popup.appendChild(select);
    document.body.appendChild(popup);

    const updatePopupPosition = () => {
      const iconRect = anchorEl.getBoundingClientRect();
      popup.style.position = "absolute";
      popup.style.left = `${window.scrollX + iconRect.left}px`;
      popup.style.top = `${window.scrollY + iconRect.top - popup.offsetHeight - 4}px`;
      popup.style.zIndex = "1000";
    };

    requestAnimationFrame(updatePopupPosition);

    const reposition = () => requestAnimationFrame(updatePopupPosition);
    window.addEventListener("scroll", reposition, true);
    window.addEventListener("resize", reposition);

    const observer = new MutationObserver(() => {
      if (!document.body.contains(popup)) {
        window.removeEventListener("scroll", reposition, true);
        window.removeEventListener("resize", reposition);
        observer.disconnect();
      }
    });
    observer.observe(document.body, { childList: true });

  }

  applyAllColumnFilters() {
    if (!this.tree) return;

    const query = this.currentQuery?.toLowerCase();
    const activeFilters = this.columnFilters;

    this.tree.visit((node) => {
      node.span?.classList.remove("wb-match");
    });

    if (activeFilters.size === 0 && !query) {
      this.tree.clearFilter();
      return;
    }

    this.tree.filterNodes((node) => {
      if (query && !node.title?.toLowerCase().includes(query)) {
        return false;
      }

      for (const [colId, value] of activeFilters.entries()) {
        const nodeVal = node.data[colId];
        if (
          nodeVal == null ||
          String(nodeVal).toLowerCase() !== value.toLowerCase()
        ) {
          return false;
        }
      }

      node.span?.classList.add("wb-match");
      return true;
    }, {
      leavesOnly: false,
      matchBranch: true,
      mode: "dim"
    });
  }

} 
