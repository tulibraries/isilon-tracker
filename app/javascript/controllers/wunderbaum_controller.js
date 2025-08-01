// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, 
                    volumeId: Number };

  async connect() {
    try {
      const res = await fetch(this.urlValue);
      const data = await res.json();
      console.log("Wunderbaum connect, url:", this.urlValue);

      new Wunderbaum({
        element: this.element,
        id: "filetree",
        source: data,
        checkbox: true,
        keyboard: true,
        keyAttr: "id",
        autoActivate: true,
        columnsResizable: true, 
        selectMode: "hier",
        lazy: true,
        columns: [
          { id: "*",
            title: "Filename",
            width: "500px",
            resizable: false
          },
          {
            id:      "migration_status",
            title:   "Migration status",
            width:   "150px",    
            classes: "wb-helper-center",
            html: `
              <select tabindex="-1">
                <option value="pending" selected>Pending</option>
              </select>`
          },
          {
            id:      "assigned_to",
            title:   "Assigned To",
            width:   "150px",
            classes: "wb-helper-center",
            html: `
              <select tabindex="-1">
                <option value="unassigned" selected>Unassigned</option>
              </select>`
          },
          { id: "file_size",
            title: "File size",
            classes: "wb-helper-center",
            width: "150px"
          },
          { id: "notes",
            title: "Notes",
            width: "500px",
            classes: "wb-helper-center",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id:      "contentdm_collection",
            title:   "Contentdm Collection",
            width:   "150px",
            classes: "wb-helper-center",
            html: `
              <select tabindex="-1">
                <option value="" selected></option>
              </select>`
          },
          {
            id:      "aspace_collection",
            title:   "ASpace Collection",
            width:   "150px",
            classes: "wb-helper-center",
            html: `
              <select tabindex="-1">
                <option value="" selected></option>
              </select>`
          },
          { id: "preservica_reference_id",
            title: "Preservica Reference",
            classes: "wb-helper-center",
            width: "150px",
            html: `<input type="text" tabindex="-1">`
          },
          {
            id:      "aspace_linking_status",
            title:   "ASpace linking status",
            width:   "150px",
            classes: "wb-helper-center",
            html:    `<input type="checkbox" tabindex="-1">`
          },
          { id: "isilon_date",
            title: "Isilon date created",
            classes: "wb-helper-center",
            width: "150px"
          },
        ],
        
        icon: ({ node }) => {
          if (!node.data.folder) {
            return "bi bi-files";
          }
        },

        // tell Wunderbaum how to fetch one folder’s children
        lazyLoad: (e) => {
          return {
            url: `/volumes/${this.volumeIdValue}/file_tree_children.json` +
                `?parent_folder_id=${encodeURIComponent(e.node.data.id)}`,
          };
        },

        init: (e) => {
          // e.tree.rootNode.children holds your top-level folder nodes
          for (const folderNode of e.tree.rootNode.children) {
            if (folderNode.data.folder) {
              folderNode.load();
            }
          }
        },

        render(e) {
          // Render each cell, hiding asset values for folders
          const util = e.util;
          const isFolder = e.node.data.folder === true;
          for (const colInfo of Object.values(e.renderColInfosById)) {
            let value = e.node.data[colInfo.id];
            if (isFolder || value == null) {
              value = "";
            }
            util.setValueToElem(colInfo.elem, value);
          }

          if (!isFolder) {
            e.nodeElem.querySelector("span.wb-title").innerHTML = `<a href="${e.node.data.url}" class="asset-link">${e.node.title}</a>`;
          }
        },

        change(e) {
          const util = e.util;
          const colId = e.info.colId;
          e.node.data[colId] = util.getValueFromElem(e.inputElem, true);
        },
      });

    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
  }
}
