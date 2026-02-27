#!/usr/bin/env bash
set -e

rails db:prepare
rails users:sync_initial
rm -f /app/.internal_test_app/tmp/pids/server.pid

exec "$@"
