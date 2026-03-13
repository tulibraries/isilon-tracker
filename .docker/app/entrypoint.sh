#!/usr/bin/env bash
set -e

<<<<<<< Updated upstream
rails db:prepare
rails users:sync_initial
=======
mkdir -p /secure-tmp/log
chmod 700 /secure-tmp/log

rails db:migrate 2>/dev/null || rails db:setup
>>>>>>> Stashed changes
rm -f /app/.internal_test_app/tmp/pids/server.pid

exec "$@"
