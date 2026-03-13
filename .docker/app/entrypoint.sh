#!/usr/bin/env bash
set -e

mkdir -p /secure-tmp
chmod 700 /secure-tmp
mkdir -p /secure-tmp/log
chmod 700 /secure-tmp/log

rails db:migrate 2>/dev/null || rails db:setup
rm -f /app/.internal_test_app/tmp/pids/server.pid

exec "$@"
