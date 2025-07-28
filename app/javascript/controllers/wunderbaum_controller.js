// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";

export default class extends Controller {
  static values = { url: String };

  async connect() {
    try {
      const res = await fetch(this.urlValue);
      const data = await res.json();

      new Wunderbaum({
        element: this.element,
        id: "filetree",
        source: data,
        checkbox: true,
        selectMode: 3, // 1=single, 2=multi, 3=hierarchical
        lazy: true,
        columns: [
          { id: "*", title: "Name", width: "500px" },
          { id: "status", title: "Status", width: "200px" },
          { id: "assigned_to", title: "Assigned To", width: "400px" },

        ],
        icon: ({ node }) => {
        // folders already get the folder icon, so:
        if (!node.data.folder) {
          // this covers *all* leaf nodes (your assets)
          return "bi bi-files";
        }
      },
        render: function (e) {
          console.log("NODE TYPE:", e.node);

          const node = e.node;

          for (const col of Object.values(e.renderColInfosById)) {
            switch (col.id) {
              default:
                // Assumption: we named column.id === node.data.NAME
                col.elem.textContent = node.data[col.id];
                break;
            }
          }
        },
        select: function (e) {
          e.node.fixSelection3AfterClick(); // 👈 applies cascading selection logic
        },
        types: {},
        init: (e) => {
          // Example: auto-activate a node
          // e.tree.findFirst("SomeFolderName")?.setActive(true);
        }
      });
    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
    
  }
}