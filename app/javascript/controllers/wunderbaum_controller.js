// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String, 
                    volumeId: Number };

  async connect() {
    try {
      // Fetch tree data and migration statuses
      const [treeRes, statusRes, aspaceRes, contentdmRes] = await Promise.all([
        fetch(this.urlValue),
        fetch("/migration_statuses.json"),
        fetch("/aspace_collections.json"),
        fetch("/contentdm_collections.json")
      ]);
      const data = await treeRes.json();
      const migrationStatuses = await statusRes.json();
      const aspaceCollections = await aspaceRes.json();
      const contentdmCollections = await contentdmRes.json();

      // Build options arrays for Wunderbaum select columns
      const migrationStatusOptions = Object.entries(migrationStatuses).map(([id, name]) => ({
        value: String(id),
        label: name
      }));

      const aspaceCollectionOptions = Object.entries(aspaceCollections).map(([id, name]) => ({
        value: String(id),
        label: name
      }));

      const contentdmCollectionOptions = Object.entries(contentdmCollections).map(([id, name]) => ({
        value: String(id),
        label: name
      }));

      // build a standalone HTML select (not needed for Wunderbaum grid editing)
      function buildMigrationStatusSelect(migrationStatusOptions, assignedStatus) {
        const select = document.createElement("select");
        select.name = "migration_status";
        migrationStatusOptions.forEach(opt => {
          const option = document.createElement("option");
          option.value = opt.value;
          option.textContent = opt.label;
          if (String(opt.value) === String(assignedStatus)) {
            option.selected = true;
          }
          select.appendChild(option);
        });
        return select;
      }

      const nodes = data.root_folders; // <-- array of nodes

      new Wunderbaum({
        element: this.element,
        id: "filetree",
        source: nodes,
        checkbox: true,
        fixedCol: true,
        keyboard: true,
        keyAttr: "id",
        autoActivate: true,
        columnsResizable: true, 
        selectMode: "hier",
        lazy: true,
        columns: [
          { id: "*",
            title: "Filename",
            width: "500px"
          },
          {
            id:      "migration_status",
            title:   "Migration status",
            width:   "150px",    
            classes: "wb-helper-center"
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
            classes: "wb-helper-center"
          },
          {
            id:      "aspace_collection",
            title:   "ASpace Collection",
            width:   "150px",
            classes: "wb-helper-center"
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
          const util = e.util;
          const isFolder = e.node.data.folder === true;

          for (const colInfo of Object.values(e.renderColInfosById)) {
            let value = e.node.data[colInfo.id];
            if (!isFolder) {
              let selectElem;
              switch (colInfo.id) {
                case "migration_status":
                  // Build and inject the select element
                  selectElem = buildMigrationStatusSelect(
                    migrationStatusOptions,
                    value
                  );
                  colInfo.elem.innerHTML = "";
                  colInfo.elem.appendChild(selectElem);
                  break;
                case "aspace_collection":
                  // Build and inject the select element
                  selectElem = buildMigrationStatusSelect(
                    aspaceCollectionOptions,
                    value
                  );
                  colInfo.elem.innerHTML = "";
                  colInfo.elem.appendChild(selectElem);
                  break;
                case "contentdm_collection":
                  // Build and inject the select element
                  selectElem = buildMigrationStatusSelect(
                    contentdmCollectionOptions,
                    value
                  );
                  colInfo.elem.innerHTML = "";
                  colInfo.elem.appendChild(selectElem);
                  break;
                // Add more cases for other custom columns if needed
                default:
                  if (value == null) value = "";
                  util.setValueToElem(colInfo.elem, value);
              }
            } else {
              // For folders, clear or set as needed
              util.setValueToElem(colInfo.elem, "");
            }
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
  }
}
