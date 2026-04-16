import { Application } from "@hotwired/stimulus";
import WunderbaumController from "controllers/wunderbaum_controller";
import BatchActionsController from "controllers/batch_actions_controller";
import SessionTimeoutController from "controllers/session_timeout_controller";

const application = Application.start();

application.register("wunderbaum", WunderbaumController);
application.register("batch-actions", BatchActionsController);
application.register("session-timeout", SessionTimeoutController);

export { application }
