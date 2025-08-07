import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, volumeId: Number };

  columnFilters = new Map();


  connect() {
    document.addEventListener("click", this.handleFilterCommandClick);
    this.initTree();
  }

  disconnect() {
    document.removeEventListener("click", this.handleFilterCommandClick);
  }

  async initTree() {
    try {
      const res = await fetch(this.urlValue);
      const data = await res.json();

      this.tree = new Wunderbaum({
        element: this.element,
        autoActivate: true,
        checkbox: true,
        columnsResizable: true,
        fixedCol: true,
        id: "tree",
        keyboard: true,
        keyAttr: "id",
        lazy: true,
        selectMode: "hier",
        source: data,

        columns: [
          { id: "*", title: "Filename", width: "500px" },
          {
            id: "migration_status",
            title: "Migration status",
            width: "150px",
            filterable: true,
            classes: "wb-helper-center",
            html: `<select tabindex="-1"><option value="pending" selected>Pending</option></select>`
          },
          {
            id: "assigned_to",
            filterable: true,
            title: "Assigned To",
            width: "150px",
            classes: "wb-helper-center",
            html: `<select tabindex="-1"><option value="unassigned" selected>Unassigned</option></select>`
          },
          { id: "file_size", title: "File size", classes: "wb-helper-center", width: "150px" },
          {
            id: "notes",
            title: "Notes",
            width: "500px",
            classes: "wb-helper-center",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id: "contentdm_collection",
            filterable: true,
            title: "Contentdm Collection",
            width: "150px",
            classes: "wb-helper-center",
            html: `<select tabindex="-1"><option value="" selected></option></select>`
          },
          {
            id: "aspace_collection",
            filterable: true,
            title: "ASpace Collection",
            width: "150px",
            classes: "wb-helper-center",
            html: `<select tabindex="-1"><option value="" selected></option></select>`
          },
          {
            id: "preservica_reference_id",
            title: "Preservica Reference",
            classes: "wb-helper-center",
            width: "150px",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id: "aspace_linking_status",
            filterable: true,
            title: "ASpace linking status",
            width: "150px",
            classes: "wb-helper-center",
            html: `<input type="checkbox" tabindex="-1">`
          },
          {
            id: "isilon_date",
            title: "Isilon date created",
            classes: "wb-helper-center",
            width: "150px"
          }
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
          if (!node.data.folder) return "bi bi-files";
        },

        lazyLoad: (e) => {
          return {
            url: `/volumes/${this.volumeIdValue}/file_tree_children.json?parent_folder_id=${encodeURIComponent(e.node.data.id)}`
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

        change: (e) => {
          const colId = e.info.colId;
          e.node.data[colId] = e.util.getValueFromElem(e.inputElem, true);
        }
      });

      this.setupInlineFilter();

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
  }

 setupInlineFilter() {
  const filterInput = document.getElementById("tree-filter");

  filterInput.addEventListener("input", async (e) => {
    const query = e.target.value.trim().toLowerCase();
    this.currentQuery = query;

    // Remove existing match highlight
    this.tree.visit((node) => {
      node.span?.classList.remove("wb-match");
    });

    if (query === "") {
      this.tree.clearFilter();
      return;
    }

    try {
      const res = await fetch(`/volumes/${this.volumeIdValue}/file_tree_search?q=${encodeURIComponent(query)}`);
      const matches = await res.json(); // should be flat array of nodes with `path`, `id`, `folder`
console.log("Search results:", matches);
      // Step 1: Ensure all ancestors are expanded
      for (const result of matches) {
  for (const ancestorId of result.path || []) {
    let ancestor = null;

    this.tree.visit((node) => {
      if (node.key === ancestorId) {
        ancestor = node;
        return false;
      }
    });

    if (ancestor && ancestor.lazy && !ancestor.children) {
      await ancestor.loadLazy(); // Expand folder
    }
  }
}


      // Step 2: Build a Set of matched IDs
      const matchIds = new Set(matches.map((m) => m.id));

      // Step 3: Filter visible nodes in place
      this.tree.filterNodes((node) => {
        const isMatch = matchIds.has(node.key);
        if (isMatch) node.span?.classList.add("wb-match");
        return isMatch;
      }, {
        leavesOnly: false,
        mode: "dim",
        matchBranch: true
      });

    } catch (err) {
      console.error("Backend search failed:", err);
    }
  });
}



  showDropdownFilter(anchorEl, colId) {
    const popupSelector = `[data-popup-for='${colId}']`;
    const existing = document.querySelector(popupSelector);

    // If popup already open, remove it (toggle off)
    if (existing) {
      existing.remove();
      return;
    }

    // Create popup container
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

    // Handle filtering
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

    // Position the popup above the filter icon
    const updatePopupPosition = () => {
      const iconRect = anchorEl.getBoundingClientRect();
      popup.style.position = "absolute";
      popup.style.left = `${window.scrollX + iconRect.left}px`;
      popup.style.top = `${window.scrollY + iconRect.top - popup.offsetHeight - 4}px`;
      popup.style.zIndex = "1000";
    };

    // Initial positioning
    requestAnimationFrame(updatePopupPosition);

    // Reposition on scroll and resize
    const reposition = () => requestAnimationFrame(updatePopupPosition);
    window.addEventListener("scroll", reposition, true);
    window.addEventListener("resize", reposition);

    // Remove listeners when popup is removed
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

    // Clear any visual match markers first
    this.tree.visit((node) => {
      node.span?.classList.remove("wb-match");
    });

    // If no filters at all, clear
    if (activeFilters.size === 0 && !query) {
      this.tree.clearFilter();
      return;
    }

    this.tree.filterNodes((node) => {
      // 1. Apply global search (filename/title)
      if (query && !node.title?.toLowerCase().includes(query)) {
        return false;
      }

      // 2. Apply all active column filters
      for (const [colId, value] of activeFilters.entries()) {
        const nodeVal = node.data[colId];
        if (
          nodeVal == null ||
          String(nodeVal).toLowerCase() !== value.toLowerCase()
        ) {
          return false;
        }
      }

      // If all pass:
      node.span?.classList.add("wb-match");
      return true;
    }, {
      leavesOnly: false,
      matchBranch: true,
      mode: "dim"
    });
  }

}
