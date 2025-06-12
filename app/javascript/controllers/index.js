import { Application } from "@hotwired/stimulus";

const application = Application.start();

import WunderbaumController from "./wunderbaum_controller";
application.register("wunderbaum", WunderbaumController);
