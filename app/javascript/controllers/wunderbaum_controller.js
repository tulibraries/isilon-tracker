// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, 
                    volumeId: Number };
  columnFilters = new Map();

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
        keyAttr: "id",
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

        init: (e) => {
          const root = (e.tree.getRootNode && e.tree.getRootNode()) || e.tree.root;
          if (root && root.lazy && !root.children) {
            root.loadLazy();
          }
        },

        lazyLoad: (e) => {
          return {
            url: `/volumes/${this.volumeIdValue}/file_tree_folders.json?parent_folder_id=${encodeURIComponent(e.node.data.id)}`,
            options: { headers: { Accept: "application/json" } }
          };
        },

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
  const input = document.getElementById("tree-filter");
  if (!input) return;

  let debounceTimer = null;
  let inflight = null; // AbortController for preload fetch
  let seq = 0;         // stale-response guard

  // Re-apply *your* filter/predicate/highlighting
  const reapply = () => {
    if (this.tree?.reapplyFilter) this.tree.reapplyFilter();
    else this.applyAllColumnFilters?.();
  };

  // Find node by key (string-safe), walking tree if needed
  const findNodeById = (id) => {
    const key = String(id);
    let n = this.tree.getNodeByKey?.(key);
    if (n) return n;
    this.tree.visit(node => {
      if (String(node.key) === key) { n = node; return false; }
    });
    return n;
  };

  // Ensure a single chain of ids is loaded in order (root->...->target)
  const ensureChainLoaded = async (ids, mySeq) => {
    for (const id of ids) {
      if (mySeq !== seq) return; // stale keystroke, stop
      const node = findNodeById(id);
      if (!node) return; // parent not present yet; bail for this chain
      if (node.lazy && !node.children && !node.data.__preloadedForSearch) {
        await node.loadLazy();
        node.data.__preloadedForSearch = true;
        reapply();                         // newly added children now get highlighted
        await new Promise(requestAnimationFrame); // let DOM paint
      }
    }
  };

  input.addEventListener("input", (e) => {
    const query = e.target.value.trim().toLowerCase();
    this.currentQuery = query;

    // Always set the filter the same way your popup does
    this.applyAllColumnFilters?.();

    // If empty, cancel any pending preload work
    if (!query) {
      if (inflight) inflight.abort();
      return;
    }

    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(async () => {
      const mySeq = ++seq;

      // cancel prior background request
      if (inflight) inflight.abort();
      inflight = new AbortController();

      try {
        // Use server search ONLY to know which chains to load
        const res = await fetch(
          `/volumes/${this.volumeIdValue}/file_tree_search?q=${encodeURIComponent(query)}`,
          { headers: { Accept: "application/json" }, credentials: "same-origin", signal: inflight.signal }
        );
        if (!res.ok) return;
        const matches = await res.json();
        if (mySeq !== seq) return; // stale response

        // Build ordered chains for each match:
        //   ancestors path [...], then target folder id:
        //   - folder hit: target = folder.id
        //   - asset hit:  target = asset.parent_folder_id
        const chains = [];
        for (const r of matches) {
          const path = Array.isArray(r.path) ? r.path.map(String) : [];
          const targetId =
            r.folder === true
              ? String(r.id)
              : String(r.parent_folder_id ?? r.folder_id ?? r.parent_id ?? "");
          const chain = [...path, targetId].filter(Boolean);
          // Deduplicate consecutive dupes, just in case
          const compact = [];
          for (const id of chain) if (compact[compact.length - 1] !== id) compact.push(id);
          if (compact.length) chains.push(compact);
        }

        // Load each chain sequentially (breadth-first across chains would also work;
        // sequential keeps requests sane and avoids race conditions)
        for (const chain of chains) {
          if (mySeq !== seq) return;
          await ensureChainLoaded(chain, mySeq);
        }

        // Final pass to catch anything appended at the tail
        reapply();
        setTimeout(reapply, 0);

      } catch (err) {
        if (err?.name !== "AbortError") {
          // ignore hard failures; client-side filtering still active
        }
      } finally {
        if (inflight && inflight.signal?.aborted === false) inflight = null;
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
