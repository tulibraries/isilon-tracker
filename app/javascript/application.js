import "@hotwired/turbo-rails";
import { application } from "./controllers";
window.Stimulus = application;
import * as bootstrap from "bootstrap";
window.bootstrap = bootstrap; // Make Bootstrap globally available

import { Wunderbaum } from "wunderbaum/dist/wunderbaum.esm.js"
window.Wunderbaum = Wunderbaum; // Make Wunderbaum globally available
