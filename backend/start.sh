#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if command -v node >/dev/null 2>&1; then
  NODE_BIN=$(command -v node)
elif [ -x /Applications/Codex.app/Contents/Resources/node ]; then
  NODE_BIN=/Applications/Codex.app/Contents/Resources/node
else
  echo "Node.js was not found. Install Node.js or run this backend from Codex." >&2
  exit 1
fi

exec "$NODE_BIN" "$SCRIPT_DIR/server.mjs"
