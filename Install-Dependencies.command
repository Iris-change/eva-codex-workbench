#!/bin/bash
export PATH="${PATH:-/usr/bin:/bin}:/opt/homebrew/bin:/usr/local/bin"
ROOT="$(cd "$(dirname "$0")" && pwd)" || exit 1
if ! command -v npm >/dev/null 2>&1; then
  printf 'Node.js 20+ (including npm) is required. Install Node.js, then try again.\n'
  read -r -p 'Press Return to close. '
  exit 1
fi
cd "$ROOT" || exit 1
npm run setup
status=$?
if [ "$status" -ne 0 ]; then read -r -p 'Press Return to close. '; fi
exit "$status"
