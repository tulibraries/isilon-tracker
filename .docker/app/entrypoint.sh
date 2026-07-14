#!/usr/bin/env bash
set -e

rails db:migrate

rm -f /app/.internal_test_app/tmp/pids/server.pid

exec "$@"
