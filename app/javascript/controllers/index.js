import { Application } from "@hotwired/stimulus";
import WunderbaumController from "./wunderbaum_controller";

const application = Application.start();

application.register("wunderbaum", WunderbaumController);

export { application }