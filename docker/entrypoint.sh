#!/bin/sh
set -e

# A hard container stop leaves this behind and Puma refuses to boot with it.
rm -f /app/tmp/pids/server.pid

# Picks up Gemfile changes without rebuilding the image.
bundle check || bundle install

exec "$@"
