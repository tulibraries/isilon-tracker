// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

let migrationStatuses = [];

export default class extends Controller {
  static values = { url: String, 
                    volumeId: Number };

  async connect() {
    Promise.all([
      fetch('/migration_statuses.json').then(res => res.json()),
      fetch('/aspace_collections.json').then(res => res.json()),
      fetch('/contentdm_collections.json').then(res => res.json())
    ]).then(([migrationStatuses, aspaceCollections, contentdmCollections]) => {
      try {
        new Wunderbaum({
          element: this.element,
          id: "filetree",
          source: data,
          checkbox: true,
          fixedCol: true,
          keyboard: true,
          keyAttr: "id",
          autoActivate: true,
          columnsResizable: true, 
          selectMode: "hier",
          lazy: true,
          grid: true,
          edit: true,
          columns: [
            { id: "*",
              title: "Filename",
              width: "500px"
            },
            {
              id:      "migration_status",
              title:   "Migration status",
              name:    "migration_status",
              editable: true,
              type:   "select",
              options: migrationStatuses.map(status => ({
                value: status.id,
                label: status.name
              }))
            }
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
            const root = e.tree?.rootNode;
            const children = root?.children;

            if (!Array.isArray(children)) return;

            for (const folderNode of children) {
              if (folderNode.data?.folder) {
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
              e.nodeElem.querySelector("span.wb-title").innerHTML = `<a href="${e.node.data.url}" class="asset-link" data-turbo="false">${e.node.title}</a>`;
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
    });
  }
}
