#!/bin/bash
# Finder may not inherit Homebrew's PATH. Keep the caller's tools first.
export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin"
ROOT="$(cd "$(dirname "$0")" && pwd)" || exit 1
if ! command -v node >/dev/null 2>&1; then
  printf 'Node.js 20+ is required. Install Node.js, then try again.\n'
  read -r -p 'Press Return to close. '
  exit 1
fi
node "$ROOT/workbench/start-macos.cjs" "$@"
status=$?
if [ "$status" -ne 0 ]; then read -r -p 'Press Return to close. '; fi
exit "$status"
