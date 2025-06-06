// app/javascript/controllers/wunderbaum_controller.js
import { Controller } from "@hotwired/stimulus";
import { Wunderbaum } from "wunderbaum";
import "wunderbaum/dist/wunderbaum.css";

export default class extends Controller {
  static values = { url: String };

  async connect() {
    try {
      const res = await fetch(this.urlValue);
      const data = await res.json();

      console.log("✅ Wunderbaum data:", data);

      new Wunderbaum({
        element: this.element,
        id: "filetree",
        source: data,
        columns: [{ id: "*", title: "Name"}],
        types: {},
        init: (e) => {
          // Example: auto-activate a node
          // e.tree.findFirst("SomeFolderName")?.setActive(true);
        },
        activate: (e) => {
          console.log("Activated node:", e.node);
        }
      });
    } catch (err) {
      console.error("Wunderbaum failed to load:", err);
    }
  }
}