pin "application", preload: true
pin "controllers", to: "controllers/index.js"
pin "@hotwired/turbo-rails", to: "turbo.min.js", preload: true
pin "@hotwired/stimulus", to: "stimulus.min.js", preload: true
pin "bootstrap", to: "https://ga.jspm.io/npm:bootstrap@5.3.8/dist/js/bootstrap.esm.js", preload: true
pin "@popperjs/core", to: "https://ga.jspm.io/npm:@popperjs/core@2.11.8/lib/index.js"
pin "chartkick", to: "https://ga.jspm.io/npm:chartkick@5.0.1/dist/chartkick.esm.js", preload: true
pin "chart.js/auto", to: "https://ga.jspm.io/npm:chart.js@4.5.1/auto/auto.js", preload: true
pin "@kurkle/color", to: "https://ga.jspm.io/npm:@kurkle/color@0.3.4/dist/color.esm.js"
pin "wunderbaum", to: "https://ga.jspm.io/npm:wunderbaum@0.13.0/dist/wunderbaum.esm.js", preload: true
pin_all_from "app/javascript/controllers", under: "controllers"
